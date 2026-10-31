require 'json'
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

class WorkflowsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  LABELS = %w[1-think 2-plan 3-code 4-release].freeze
  PHASES = %w[think plan code prove].freeze

  def setup
    @directory = Dir.mktmpdir('coding-pal-workflows-')
    bin = File.join(@directory, 'bin')
    Dir.mkdir(bin)
    %w[bash jq mkdir head uname].each do |command|
      executable = ENV.fetch('PATH').split(File::PATH_SEPARATOR)
                      .map { |path| File.join(path, command) }
                      .find { |path| File.executable?(path) && !File.directory?(path) }
      raise "Required test tool is missing: #{command}" unless executable
      File.symlink(executable, File.join(bin, command))
    end
    mock = File.join(bin, 'gh')
    File.write(mock, "#!#{RbConfig.ruby}\nload #{File.join(__dir__, 'support/gh.rb').inspect}\n")
    File.chmod(0o755, mock)
    @environment = {
      'PATH' => bin, 'HOME' => @directory, 'LC_ALL' => 'C', 'RUBYOPT' => '-EUTF-8',
      'GH_TOKEN' => 'fake-test-token', 'OWNER' => 'test-owner', 'REPO' => 'test-repo',
      'ISSUE_NUMBER' => '42', 'PR_NUMBER' => '99', 'PR_URL' => 'https://example.test/pr/99',
      'PROJECT_TITLE' => 'Test board', 'EVENT_NAME' => 'issues',
      'GITHUB_OUTPUT' => File.join(@directory, 'output'),
      'GITHUB_ENV' => File.join(@directory, 'environment'),
      'TEST_SCENARIO' => File.join(@directory, 'scenario.json'),
      'TEST_CALLS' => File.join(@directory, 'calls.jsonl'),
      'TEST_VIOLATIONS' => File.join(@directory, 'violations')
    }
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory
  end

  def workflow(phase)
    YAML.load_file(File.join(ROOT, ".github/workflows/pipeline-#{phase}.yml"))
  end

  def steps(phase)
    workflow(phase).fetch('jobs').fetch(phase).fetch('steps')
  end

  def step(phase, id)
    steps(phase).find { |entry| entry['id'] == id } || raise("Missing #{phase} step #{id}")
  end

  def scenario(labels = [], comments: [], prs: [], queue: [], **extra)
    {
      'issue' => { 'labels' => labels.map { |name| { 'name' => name } },
                   'body' => '', 'comments' => comments.map { |body| { 'body' => body } } },
      'prs' => prs, 'queue' => queue
    }.merge(extra.transform_keys(&:to_s))
  end

  def run_step(entry, data, environment = {}, success: true)
    script = entry.fetch('run')
    refute_includes script, '${{', 'Tested shell steps must take Actions expressions through env'
    File.write(@environment.fetch('TEST_SCENARIO'), JSON.generate(data))
    %w[GITHUB_OUTPUT GITHUB_ENV TEST_CALLS TEST_VIOLATIONS].each do |key|
      File.write(@environment.fetch(key), '')
    end
    literals = entry.fetch('env', {}).reject { |_, value| value.to_s.include?('${{') }
    @stdout, stderr, status = Open3.capture3(
      @environment.merge(literals).merge(environment),
      File.join(@directory, 'bin/bash'), '--noprofile', '--norc', '-e', '-o', 'pipefail',
      stdin_data: script, chdir: @directory, unsetenv_others: true
    )
    assert_equal '', File.read(@environment.fetch('TEST_VIOLATIONS')), 'Unmocked GitHub operation attempted'
    assert_equal success, status.success?, "#{@stdout}\n#{stderr}"
    @calls = File.readlines(@environment.fetch('TEST_CALLS')).map { |line| JSON.parse(line) }
    File.readlines(@environment.fetch('GITHUB_OUTPUT')).to_h { |line| line.strip.split('=', 2) }
  end

  def dispatches
    @calls.select { |args| args.first(2) == %w[workflow run] }
  end

  def queue_issue(number, labels, timestamp = '2026-01-02T00:00:00Z')
    {
      'number' => number, 'createdAt' => '2025-01-01T00:00:00Z',
      'labels' => { 'nodes' => labels.map { |name| { 'name' => name } } },
      'timelineItems' => { 'nodes' => labels.map { |name| { 'label' => { 'name' => name }, 'createdAt' => timestamp } } }
    }
  end

  def test_all_embedded_shell_scripts_parse
    Dir.glob(File.join(ROOT, '.github/workflows/*.yml')).each do |path|
      YAML.load_file(path).fetch('jobs').each_value do |job|
        Array(job['steps']).each do |entry|
          next unless entry['run']
          _, error, status = Open3.capture3('bash', '-n', stdin_data: entry['run'])
          assert status.success?, "#{path}: #{entry['name']}\n#{error}"
        end

      end
    end
  end

  def test_copilot_and_github_credentials_are_separate
    workflows = (PHASES + %w[publish-npm upstream-resume]).map { |phase| workflow(phase) }
    workflows << YAML.load_file(File.join(ROOT, '.github/workflows/audit-runner.yml'))
    workflows.each do |current|
      triggers = current['on'] || current.fetch(true)
      secrets = triggers.fetch('workflow_call').fetch('secrets')
      assert secrets.key?('PIPELINE_GITHUB_TOKEN'), current.fetch('name')
      current.fetch('jobs').each_value do |job|
        Array(job['steps']).each do |entry|
          environment = entry.fetch('env', {})
          if environment.key?('GH_TOKEN')
            assert_equal '${{ secrets.PIPELINE_GITHUB_TOKEN }}', environment.fetch('GH_TOKEN'), entry['name']
          end
          if entry.fetch('run', '').match?(/\bcopilot --/)
            assert_equal '${{ secrets.COPILOT_GITHUB_TOKEN }}', environment.fetch('COPILOT_GITHUB_TOKEN'), entry['name']
            assert_equal '${{ secrets.PIPELINE_GITHUB_TOKEN }}', environment.fetch('GH_TOKEN'), entry['name']
          end
          entry.fetch('with', {}).each_value do |value|
            refute_includes value.to_s, 'secrets.COPILOT_GITHUB_TOKEN'
          end
        end
      end
    end
    (PHASES + ['upstream-resume']).each do |phase|
      current = workflow(phase)
      triggers = current['on'] || current.fetch(true)
      assert triggers.dig('workflow_call', 'secrets', 'PIPELINE_GITHUB_TOKEN', 'required')
    end
    %w[code prove].each do |phase|
      checkout = steps(phase).find { |entry| entry['uses'].to_s.start_with?('actions/checkout@') }
      assert_equal '${{ secrets.PIPELINE_GITHUB_TOKEN }}', checkout.dig('with', 'token')
    end
    audit = YAML.load_file(File.join(ROOT, '.github/workflows/audit-runner.yml'))
    triggers = audit['on'] || audit.fetch(true)
    assert triggers.dig('workflow_call', 'secrets', 'PIPELINE_GITHUB_TOKEN', 'required')
    checkout = audit.fetch('jobs').fetch('audit').fetch('steps').first
    assert_equal '${{ secrets.PIPELINE_GITHUB_TOKEN }}', checkout.dig('with', 'token')
  end

  def test_every_copilot_invocation_uses_auto
    calls = []
    Dir.glob(File.join(ROOT, '.github/workflows/*.yml')).each do |path|
      YAML.load_file(path).fetch('jobs').each_value do |job|
        Array(job['steps']).each do |entry|
          entry.fetch('run', '').each_line do |line|
            next unless line.match?(/^\s*copilot\s/)
            calls << line
            assert_match(/^\s*copilot --model="auto"(?:\s|$)/, line, "#{path}: #{entry['name']}")
            refute_match(/--(?:fusion-tier|auto-tier|reasoning-effort)\b/, line)
          end
        end
      end
    end
    assert_equal 8, calls.length
  end

  def test_publish_checks_pipeline_credentials_before_publishing
    entries = workflow('publish-npm').fetch('jobs').fetch('publish').fetch('steps')
    check = entries.find { |entry| entry['name'] == 'Check downstream notification credentials' }
    assert_equal 'inputs.dry_run != true', check.fetch('if')
    assert_operator entries.index(check), :<, entries.index { |entry| entry['name'] == 'Publish package to npm' }
    run_step(check, scenario, { 'GH_TOKEN' => '' }, success: false)
    assert_includes @stdout, '::error::PIPELINE_GITHUB_TOKEN'
    assert_empty @calls
    run_step(check, scenario)
    assert_empty @calls
  end

  def test_shared_workflow_references_resolve_to_existing_files
    paths = Dir.glob(File.join(ROOT, '.github/workflows/*.yml'))
    if ENV['PROJECT_WORKFLOWS_ROOT']
      paths += Dir.glob(File.join(ENV.fetch('PROJECT_WORKFLOWS_ROOT'), '*/.github/workflows/*.yml'))
    end
    paths.uniq.each do |path|
      YAML.load_file(path).fetch('jobs').each_value do |job|
        reference = job['uses'].to_s
        prefix = '1pizzateam/coding-pal/'
        next unless reference.start_with?(prefix)
        relative = reference.delete_prefix(prefix).split('@').first
        assert File.file?(File.join(ROOT, relative)), "#{path}: missing reusable workflow #{reference}"
      end
    end
    audits = Dir.glob(File.join(ROOT, '.github/workflows/*audit*.yml'))
    audits.each { |path| assert File.basename(path).start_with?('audit-'), path }
  end

  def test_checkpoints_pause_only_at_the_requested_phase
    %w[think plan code].each_with_index do |phase, index|
      LABELS.each do |label|
        output = run_step(step(phase, 'checkpoint'), scenario([label]))
        paused = label == LABELS[index]
        assert_equal paused.to_s, output.fetch('paused'), "#{phase} with #{label}"
        edits = @calls.select { |args| args.first(2) == %w[issue edit] }
        assert_equal paused ? 1 : 0, edits.length
        if paused
          edit = edits.first
          assert_equal "review:#{phase}", edit[edit.index('--add-label') + 1]
          assert_equal LABELS + ["pause:#{phase}"], edit[edit.index('--remove-label') + 1].split(',')
        end
        assert_empty dispatches
      end
    end
  end

  def test_pause_directives_are_preserved
    %w[think plan code].each do |phase|
      ["[pause:#{phase}]", "- [x] Pause after #{phase.capitalize}"].each do |body|
        data = scenario(['4-release'])
        data['issue']['body'] = body
        assert_equal 'true', run_step(step(phase, 'checkpoint'), data).fetch('paused')
      end
      data = scenario(['4-release'])
      data['issue']['body'] = "- [ ] Pause after #{phase.capitalize}"
      assert_equal 'false', run_step(step(phase, 'checkpoint'), data).fetch('paused')
    end
  end

  def test_pause_artifact_gates_prevent_downstream_workflows
    %w[think plan code].each do |phase|
      artifact = steps(phase).find { |entry| entry['uses'].to_s.start_with?('actions/upload-artifact@') }
      assert_includes artifact.fetch('if'), "steps.checkpoint.outputs.paused != 'true'"
    end
    gate = steps('think').find { |entry| entry['uses'].to_s.start_with?('actions/upload-artifact@') }.fetch('if')
    assert_includes gate, 'steps.resume.outputs.resumed_stage'
  end

  def test_downstream_dispatch_requires_a_successful_handoff
    { 'think' => 'plan', 'plan' => 'code' }.each do |phase, next_phase|
      entries = steps(phase)
      artifact = step(phase, 'handoff')
      assert artifact.fetch('uses').start_with?('actions/upload-artifact@')
      assert_includes artifact.fetch('if'), "steps.checkpoint.outputs.paused != 'true'"
      dispatch = entries.find { |entry| entry['name'] == "Start #{next_phase.capitalize}" }
      assert_equal "steps.handoff.outcome == 'success'", dispatch.fetch('if')
      assert_operator entries.index(dispatch), :>, entries.index(artifact)
      run_step(dispatch, scenario, { 'RUN_ID' => '12345' })
      assert_equal [['workflow', 'run', "#{next_phase}.yml", '-f', 'workflow_run_id=12345']], dispatches
    end
  end

  def test_preparation_does_not_wait_for_delivery_or_other_issues
    LABELS.each do |label|
      data = scenario([label], queue: [queue_issue(1, ['1-think'])],
                      runs: [{ 'status' => 'in_progress' }],
                      prs: [{ 'number' => 100, 'headRefName' => 'feature/issue-7-work', 'labels' => [] }])
      output = run_step(step('think', 'resume'), data)
      assert_equal 'none', output.fetch('resumed_stage')
      assert_empty dispatches
      refute @calls.any? { |args| args.first(2) == %w[run list] || args.first(2) == %w[api graphql] }
    end
    %w[think plan].each do |phase|
      group = workflow(phase).dig('jobs', phase, 'concurrency', 'group')
      assert_includes group, '${{ inputs.issue_number'
    end
  end

  def test_review_pauses_do_not_restart_other_issues
    %w[think plan code].each_with_index do |phase, index|
      output = run_step(step(phase, 'checkpoint'),
                        scenario([LABELS[index]], queue: [queue_issue(1, ['4-release'])]))
      assert_equal 'true', output.fetch('paused')
      assert_empty dispatches
    end
  end

  def test_code_exposes_prove_handoff_only_after_artifact_upload
    current = workflow('code')
    triggers = current['on'] || current.fetch(true)
    assert_equal '${{ jobs.code.outputs.continue_to_prove }}',
                 triggers.dig('workflow_call', 'outputs', 'continue_to_prove', 'value')
    assert_equal "${{ steps.handoff.outcome == 'success' }}",
                 current.dig('jobs', 'code', 'outputs', 'continue_to_prove')
    assert_includes step('code', 'handoff').fetch('if'), "steps.checkpoint.outputs.paused != 'true'"
    refute steps('code').any? { |entry| entry.fetch('run', '').include?('gh workflow run prove.yml') }
    refute steps('prove').any? { |entry| entry.fetch('run', '').include?('gh workflow run think.yml') }
  end

  def test_smart_resume_reuses_specs
    fifo = step('think', 'resume')
    LABELS.each do |label|
      output = run_step(fifo, scenario([label], comments: ['# Think: scope', '# Plan: steps']))
      expected = { '1-think' => 'none', '2-plan' => 'plan', '3-code' => 'code', '4-release' => 'code' }.fetch(label)
      assert_equal expected, output.fetch('resumed_stage')
      if expected == 'code'
        assert_equal [['workflow', 'run', 'code.yml', '-f', 'issue_number=42']], dispatches
      elsif expected == 'plan'
        assert_equal "# Think: scope\n", File.read(File.join(@directory, 'specs/issue-42/think.md'))
        assert_empty dispatches
      else
        assert_empty dispatches
      end
    end
    assert_equal 'plan', run_step(fifo, scenario(['3-code'], comments: ['# Think: scope'])).fetch('resumed_stage')
    assert_equal 'none', run_step(fifo, scenario(['4-release'])).fetch('resumed_stage')
  end

  def test_existing_pr_is_proven_only_for_release
    prs = [{ 'number' => 99, 'headRefName' => 'feature/issue-42-test', 'labels' => [] }]
    %w[3-code 4-release].each do |label|
      output = run_step(step('think', 'resume'), scenario([label], prs: prs))
      assert_equal label == '4-release' ? 'prove' : 'code', output.fetch('resumed_stage')
      if label == '4-release'
        assert_equal [['workflow', 'run', 'prove.yml', '-f', 'pr_number=99', '-f', 'issue_number=42']], dispatches
      else
        assert_empty dispatches
        assert @calls.any? { |args| args.first(3) == ['pr', 'edit', '99'] && args.include?('review:code') }
      end
    end
  end

  def test_failures_remove_trigger_labels_without_restarting_other_issues
    PHASES.each do |phase|
      entry = steps(phase).find { |item| item['name'].to_s.match?(/(?:if #{phase.capitalize} fail|if #{phase.capitalize} failed)/) }
      refute_nil entry, phase
      run_step(entry, scenario([], queue: [queue_issue(7, ['1-think'])]))
      edit = @calls.find { |args| args.first(2) == %w[issue edit] }
      assert_equal 'needs:developer', edit[edit.index('--add-label') + 1]
      assert_equal LABELS, edit[edit.index('--remove-label') + 1].split(',')
      assert_empty dispatches
    end
  end

  def project
    { 'data' => { 'repository' => {
      'issue' => { 'id' => 'ISSUE' },
      'owner' => { 'projectsV2' => { 'nodes' => [{
        'id' => 'PROJECT', 'title' => 'Test board',
        'field' => { 'id' => 'STATUS', 'options' => %w[Think Plan Code Release Done].map { |name| { 'name' => name, 'id' => name.downcase } } }
      }] } }
    } } }
  end

  def status_step(phase, status)
    steps(phase).find { |entry| entry.dig('env', 'TARGET_STATUS') == status } || raise("Missing #{status}")
  end

  def test_status_updates_use_the_expected_project_and_option
    { 'think' => 'Think', 'plan' => 'Plan', 'code' => 'Code', 'prove' => 'Release' }.each do |phase, status|
      entry = status_step(phase, status)
      run_step(entry, scenario([], project: project))
      update = @calls.find { |args| args.any? { |arg| arg.start_with?('query=') && arg.include?('updateProjectV2ItemFieldValue') } }
      refute_nil update
      %W[projectId=PROJECT itemId=ITEM fieldId=STATUS optionId=#{status.downcase}].each { |arg| assert_includes update, arg }
      assert_includes entry.fetch('if'), phase == 'think' ? "steps.resume.outputs.resumed_stage == 'none'" : "steps.resolve.outputs.skip != 'true'"
    end
  end

  def test_project_status_matching_is_case_insensitive
    data = project
    board = data['data']['repository']['owner']['projectsV2']['nodes'].first
    board['title'] = 'TEST BOARD'
    board['field']['options'].each { |option| option['name'] = option['name'].downcase }
    run_step(status_step('think', 'Think'), scenario([], project: data))
    assert @calls.any? { |args| args.include?('optionId=think') }
  end

  def test_paused_code_keeps_code_status_and_adds_review_label
    status_entries = steps('code').select { |entry| entry.dig('env', 'TARGET_STATUS') }
    assert_equal ['Code'], status_entries.map { |entry| entry.dig('env', 'TARGET_STATUS') }
    run_step(status_entries.first, scenario(['3-code'], project: project))
    assert @calls.any? { |args| args.include?('optionId=code') }

    output = run_step(step('code', 'checkpoint'), scenario(['3-code'], project: project))
    assert_equal 'true', output.fetch('paused')
    edit = @calls.find { |args| args.first(2) == %w[issue edit] }
    assert_equal 'review:code', edit[edit.index('--add-label') + 1]
    refute @calls.any? { |args| args.any? { |arg| arg.include?('updateProjectV2ItemFieldValue') } }
  end

  def test_status_configuration_and_permission_errors_are_explicit
    PHASES.each do |phase|
      status = { 'think' => 'Think', 'plan' => 'Plan', 'code' => 'Code', 'prove' => 'Release' }.fetch(phase)
      entry = status_step(phase, status)
      data = scenario([], project: project)
      data['project']['data']['repository']['owner']['projectsV2']['nodes'][0]['field']['options'] = []
      run_step(entry, data, {}, success: false)
      assert_includes @stdout, '::error::'
      run_step(entry, scenario([], project: project, api_failure: true), {}, success: false)
      refute @calls.any? { |args| args.any? { |arg| arg.include?('mutation(') } }
      run_step(entry, scenario([]), { 'PROJECT_TITLE' => '' })
      assert_empty @calls
    end
  end

  def test_done_is_success_gated_and_after_release_preparation
    entries = steps('prove')
    done = status_step('prove', 'Done')
    refute_match(/always\(|failure\(/, done.fetch('if'))
    assert_operator entries.index(done), :>, entries.index { |entry| entry['name'].to_s.start_with?('Auto-release merged') }
    run_step(done, scenario([], project: project))
    assert @calls.any? { |args| args.include?('optionId=done') }
  end

  def test_autonomous_decision_validation_is_installed_for_think
    install = steps('think').find { |entry| entry['name'] == 'Install ALTEN-group/coding-pal think primitives' }.fetch('run')
    assert_includes install, 'cp -R /tmp/alten-coding-pal/skills/decision-record .agents/skills/decision-record'
    assert_includes install, 'cp /tmp/alten-coding-pal/instructions/decision-record.instructions.md .github/instructions/'
  end

  def test_high_risk_automated_metadata_is_checked_before_merge
    script = steps('prove').find { |entry| entry['name'] == 'Record automated validation, approve PR, and auto-merge' }.fetch('run')
    assert_includes script, 'readPlan, readThink'
    assert_includes script, 'if [ "$TIER" = "High" ] || [ "$TIER" = "Critical" ]'
    assert_includes script, "only when concrete rollback verification evidence is recorded"
    assert_includes script, "leave the affected field Pending"
    assert_operator script.index('--stage pass'), :<, script.index('copilot --model="auto" --agent="prove"')
    assert_operator script.index('copilot --model="auto" --agent="prove"'), :<, script.index('--stage prove')
    entries = steps('prove')
    merge = entries.find { |entry| entry['name'] == 'Verify validated revisions and merge' }
    assert_operator entries.index(merge), :>, entries.index { |entry| entry['name'] == 'Record automated validation, approve PR, and auto-merge' }
  end

  def git_command(*arguments, directory: @repository)
    output, error, status = Open3.capture3(
      { 'HOME' => @directory, 'GIT_CONFIG_NOSYSTEM' => '1' },
      'git', *arguments, chdir: directory
    )
    assert status.success?, "#{arguments.inspect}\n#{output}\n#{error}"
    output.strip
  end

  def prepare_stale_pr(conflict: false)
    @repository = File.join(@directory, 'repository')
    remote = File.join(@directory, 'remote.git')
    Dir.mkdir(@repository)
    git_command('init', '--bare', remote)
    git_command('init', '-b', 'main')
    git_command('config', 'user.name', 'Test')
    git_command('config', 'user.email', 'test@example.test')
    File.write(File.join(@repository, 'shared.txt'), "original\n")
    git_command('add', '.')
    git_command('commit', '-m', 'Initial')
    git_command('remote', 'add', 'origin', remote)
    git_command('push', 'origin', 'main')
    git_command('checkout', '-b', 'feature/issue-42-test')
    File.write(File.join(@repository, conflict ? 'shared.txt' : 'feature.txt'), "feature\n")
    git_command('add', '.')
    git_command('commit', '-m', 'Feature')
    git_command('push', 'origin', 'HEAD')
    git_command('checkout', 'main')
    File.write(File.join(@repository, 'shared.txt'), "updated base\n")
    git_command('add', '.')
    git_command('commit', '-m', 'Intervening change')
    git_command('push', 'origin', 'main')
    @base_sha = git_command('rev-parse', 'HEAD')
    git_command('checkout', 'feature/issue-42-test')
  end

  def run_freshness_script(name, data: scenario, success: true, **environment)
    entry = steps('prove').find { |item| item['name'] == name }
    File.write(@environment.fetch('TEST_SCENARIO'), JSON.generate(data))
    File.write(@environment.fetch('TEST_CALLS'), '')
    File.write(@environment.fetch('TEST_VIOLATIONS'), '')
    env = @environment.merge(
      'PATH' => "#{@environment.fetch('PATH')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      'BASE_REF' => 'main', 'BRANCH_NAME' => 'feature/issue-42-test'
    ).merge(environment.transform_keys(&:to_s))
    output, error, status = Open3.capture3(
      env, 'bash', '--noprofile', '--norc', '-eo', 'pipefail',
      stdin_data: entry.fetch('run'), chdir: @repository, unsetenv_others: true
    )
    assert_equal success, status.success?, "#{output}\n#{error}"
    assert_equal '', File.read(@environment.fetch('TEST_VIOLATIONS'))
    @calls = File.readlines(@environment.fetch('TEST_CALLS')).map { |line| JSON.parse(line) }
    output
  end

  def test_prove_refreshes_and_pushes_a_stale_branch_before_checks
    prepare_stale_pr
    run_freshness_script('Refresh PR branch against latest base')
    assert_equal "updated base\n", File.read(File.join(@repository, 'shared.txt'))
    assert_equal git_command('rev-parse', 'HEAD'),
                 git_command('rev-parse', 'refs/remotes/origin/feature/issue-42-test')
    assert_includes File.read(@environment.fetch('GITHUB_ENV')), "PROVE_BASE_SHA=#{@base_sha}"
    head = git_command('rev-parse', 'HEAD')
    run_freshness_script('Refresh PR branch against latest base')
    assert_equal head, git_command('rev-parse', 'HEAD'), 'Already-current branches must not get extra commits'
    entries = steps('prove')
    assert_operator entries.index { |entry| entry['id'] == 'freshness' }, :<,
                    entries.index { |entry| entry['name'] == 'Run Prove validation and auto-remediation loop' }
  end

  def test_conflicts_abort_without_pushing_or_merging
    prepare_stale_pr(conflict: true)
    head = git_command('rev-parse', 'HEAD')
    output = run_freshness_script('Refresh PR branch against latest base', success: false)
    assert_includes output, '::error::'
    assert_equal head, git_command('rev-parse', 'HEAD')
    assert_equal head, git_command('rev-parse', 'refs/remotes/origin/feature/issue-42-test')
    assert_equal '', git_command('status', '--porcelain')
    assert @calls.any? { |args| args.first(2) == %w[pr comment] }
    refute @calls.any? { |args| args.first(2) == %w[pr merge] }
  end

  def test_merge_requires_unchanged_base_and_exact_validated_head
    prepare_stale_pr
    run_freshness_script('Refresh PR branch against latest base')
    head = git_command('rev-parse', 'HEAD')
    name = 'Verify validated revisions and merge'
    run_freshness_script(name, data: scenario(pr: { 'headRefOid' => head }), PROVE_BASE_SHA: @base_sha)
    assert_includes @calls, ['pr', 'merge', '99', '--squash', '--delete-branch', '--match-head-commit', head]
    [
      [@base_sha, 'a' * 40],
      ['b' * 40, head]
    ].each do |base, remote_head|
      output = run_freshness_script(name, data: scenario(pr: { 'headRefOid' => remote_head }),
                                   PROVE_BASE_SHA: base, success: false)
      assert_includes output, '::error::'
      refute @calls.any? { |args| args.first(2) == %w[pr merge] }
    end
  end

  if ENV['PROJECT_WORKFLOWS_ROOT']
    def test_project_wrapper_contracts
      projects = {
        'BumpR.js' => 'BumpR', 'Cadenza' => 'Cadenza', 'DoomR.js' => 'DoomR',
        'GroovR.js' => 'GroovR', 'LoopR.js' => 'LoopR', 'MappR' => 'MappR',
        'PixelGun' => 'PixelGun', 'PolyGun' => 'PolyGun', 'RoostR.js' => 'RoostR',
        'ShaderGun' => 'ShaderGun', 'Spock.js' => 'Spock'
      }
      projects.each do |repository, title|
        directory = File.join(ENV.fetch('PROJECT_WORKFLOWS_ROOT'), repository, '.github/workflows')
        wrapper = YAML.load_file(File.join(directory, 'think.yml'))
        # Psych's YAML 1.1 parser treats the unquoted Actions "on" key as true.
        triggers = wrapper['on'] || wrapper.fetch(true)
        assert_equal ['labeled'], triggers.fetch('issues').fetch('types'), repository
        job = wrapper.fetch('jobs').fetch('think')
        assert_equal 'inherit', job.fetch('secrets'), repository
        labels = job.fetch('if').scan(/github.event.label.name == '([^']+)'/).flatten
        assert_equal LABELS, labels, repository
        expected = "github.event_name == 'workflow_dispatch' || " \
                   "(github.event_name == 'issues' && github.event.issue.state == 'open' && " \
                   "github.event.label.name != '' && (" \
                   "#{LABELS.map { |label| "github.event.label.name == '#{label}'" }.join(' || ')}))"
        assert_equal expected, job.fetch('if').split.join(' '), repository
        assert_equal title, job.fetch('with').fetch('project_title')
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-think.yml@main', job.fetch('uses')
        %w[plan code prove].each do |phase|
          current = YAML.load_file(File.join(directory, "#{phase}.yml"))
          job = current.fetch('jobs').fetch(phase)
          assert_equal 'inherit', job.fetch('secrets'), repository
          events = current['on'] || current.fetch(true)
          assert_equal ['workflow_dispatch'], events.keys, repository
          inputs = events.fetch('workflow_dispatch').fetch('inputs')
          assert_equal false, inputs.fetch('workflow_run_id').fetch('required')
          assert_equal false, inputs.fetch('issue_number').fetch('required')
          assert_equal "${{ inputs.workflow_run_id || '' }}", job.fetch('with').fetch('workflow_run_id')
          refute job.key?('if'), repository
          assert_equal "Pipeline - #{phase.capitalize}", current.fetch('name')
          if %w[code prove].include?(phase)
            assert_equal 'delivery-${{ github.repository }}', current.dig('concurrency', 'group')
            assert_equal false, current.dig('concurrency', 'cancel-in-progress')
            assert_equal 'max', current.dig('concurrency', 'queue')
          else
            refute current.key?('concurrency')
          end
        end
        code = YAML.load_file(File.join(directory, 'code.yml'))
        prove = code.fetch('jobs').fetch('prove')
        assert_equal 'code', prove.fetch('needs')
        assert_equal "needs.code.outputs.continue_to_prove == 'true'", prove.fetch('if')
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-prove.yml@main', prove.fetch('uses')
        assert_equal '${{ github.run_id }}', prove.dig('with', 'workflow_run_id')
        assert_equal title, prove.dig('with', 'project_title')
        assert_equal 'inherit', prove.fetch('secrets')
        assert_equal false, prove.dig('with', 'auto_release_npm') if repository == 'DoomR.js'
        audits = YAML.load_file(File.join(directory, 'audits.yml'))
        assert_equal 'Audit - Run audit', audits.fetch('name')
      end
    end
  end
end
