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
    %w[bash jq mkdir head uname cat rm tr sed chmod printf].each do |command|
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
      'RUNNER_TEMP' => @directory,
      'GITHUB_REPOSITORY' => 'test-owner/test-repo',
      'GITHUB_SERVER_URL' => 'https://github.com',
      'GITHUB_RUN_ID' => '123',
      'GITHUB_STEP_SUMMARY' => File.join(@directory, 'summary'),
      'ISSUE_NUMBER' => '42', 'PR_NUMBER' => '99', 'PR_URL' => 'https://example.test/pr/99',
      'GITHUB_OUTPUT' => File.join(@directory, 'output'),
      'GITHUB_ENV' => File.join(@directory, 'environment'),
      'TEST_SCENARIO' => File.join(@directory, 'scenario.json'),
      'TEST_CALLS' => File.join(@directory, 'calls.jsonl'),
      'TEST_VIOLATIONS' => File.join(@directory, 'violations')
    }
    @actions_context = {
      'secrets.PIPELINE_GITHUB_TOKEN' => 'fake-test-token',
      'secrets.COPILOT_GITHUB_TOKEN' => 'fake-copilot-token',
      'github.token' => 'fake-github-token',
      'github.repository' => 'test-owner/test-repo',
      'github.repository_owner' => 'test-owner',
      'github.event.repository.name' => 'test-repo',
      'github.event.repository.default_branch' => 'main',
      'github.run_id' => '123',
      'inputs.issue_number' => '42',
      'inputs.pr_number' => '99',
      'inputs.workflow_run_id' => '',
      'inputs.project_title' => 'Test board',
      'inputs.fix_loop_limit' => '5',
      'inputs.base_ref' => 'main',
      'inputs.prove_base_sha' => 'base-sha',
      'inputs.release_merge_sha' => 'merge-sha',
      'inputs.release_started_at' => '2026-01-02T00:00:00Z',
      'inputs.release_sha' => '',
      'inputs.release_tag' => '',
      'inputs.deployment_workflow' => '',
      'inputs.deployment_paths' => '',
      'inputs.package' => '@1pizzateam/spock',
      'inputs.version' => '1.2.3',
      'inputs.upstream_repo' => '1pizzateam/Spock.js',
      'inputs.agent' => 'dead-code',
      'inputs.scope' => 'src/',
      'inputs.prompt' => '',
      'inputs.pr_title' => 'chore: remove dead code in src/',
      'env.ISSUE_NUMBER' => '42',
      'steps.release.outputs.release_sha' => '',
      'steps.release.outputs.release_tag' => ''
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

  def resolve_actions_value(raw)
    text = raw.to_s
    return text unless text.include?('${{')

    text.gsub(/\$\{\{\s*(.*?)\s*\}\}/) do
      candidates = Regexp.last_match(1).split('||').map(&:strip)
      resolved = candidates.lazy.map { |expr| @actions_context[expr] }.find { |val| !val.nil? && !val.empty? }
      if resolved.nil?
        raise "Unmapped Actions expression #{Regexp.last_match(0)}" unless candidates.any? { |expr| @actions_context.key?(expr) }
        ''
      else
        resolved
      end
    end
  end

  def resolve_step_environment(entry)
    job_env = {}
    Dir.glob(File.join(ROOT, '.github/workflows/*.yml')).each do |path|
      YAML.load_file(path).fetch('jobs').each_value do |job|
        if Array(job['steps']).any? { |candidate| candidate['name'] == entry['name'] && candidate['id'] == entry['id'] }
          job_env = job.fetch('env', {})
        end
      end
    end
    job_env.merge(entry.fetch('env', {})).transform_values { |value| resolve_actions_value(value) }
  end

  def run_step(entry, data, environment = {}, success: true)
    script = entry.fetch('run')
    if entry['id'] == 'checkpoint' && script.include?('code-project-status.sh')
      status_script = status_step('code', 'Code').fetch('run').split("<<'STATUS_SCRIPT'\n", 2).last.split("\nSTATUS_SCRIPT", 2).first
      File.write(File.join(@directory, 'code-project-status.sh'), status_script)
      data = { 'project' => project }.merge(data)
    end
    refute_includes script, '${{', 'Tested shell steps must take Actions expressions through env'
    File.write(@environment.fetch('TEST_SCENARIO'), JSON.generate(data))
    %w[GITHUB_OUTPUT GITHUB_ENV TEST_CALLS TEST_VIOLATIONS].each do |key|
      File.write(@environment.fetch(key), '')
    end
    declared = resolve_step_environment(entry)
    @stdout, stderr, status = Open3.capture3(
      @environment.merge(declared).merge(environment),
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
          refute_includes entry['run'], '${{', "#{path}: #{entry['name']} must take Actions expressions through env"
          _, error, status = Open3.capture3('bash', '-n', stdin_data: entry['run'])
          assert status.success?, "#{path}: #{entry['name']}\n#{error}"
          entry['run'].scan(/<<'([A-Z_]+)'\n(.*?)\n\1/m).each do |_, script|
            _, error, status = Open3.capture3('bash', '-n', stdin_data: script)
            assert status.success?, "#{path}: #{entry['name']} helper\n#{error}"
          end
        end

      end
    end
  end

  def test_copilot_and_github_credentials_are_separate
    workflows = (PHASES + %w[release publish-npm upstream-resume]).map { |phase| workflow(phase) }
    workflows << YAML.load_file(File.join(ROOT, '.github/workflows/audit-runner.yml'))
    workflows.each do |current|
      triggers = current['on'] || current.fetch(true)
      secrets = triggers.fetch('workflow_call').fetch('secrets')
      assert secrets.key?('PIPELINE_GITHUB_TOKEN'), current.fetch('name')
      current.fetch('jobs').each_value do |job|
        assert_equal '${{ github.repository }}', job.dig('env', 'GH_REPO'), current.fetch('name')
        checkout_index = Array(job['steps']).index { |entry| entry['uses'].to_s.start_with?('actions/checkout@') }
        Array(job['steps']).each_with_index do |entry, index|
          environment = entry.fetch('env', {})
          if environment.key?('GH_TOKEN')
            assert_equal '${{ secrets.PIPELINE_GITHUB_TOKEN }}', environment.fetch('GH_TOKEN'), entry['name']
            if (checkout_index.nil? || index < checkout_index || entry['if'].to_s.include?('failure()')) &&
               entry.fetch('run', '').match?(/\bgh\s+(?!api\b)/)
              assert_equal '${{ github.repository }}', environment.fetch('GH_REPO'), entry['name']
            end
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
    (PHASES + %w[release upstream-resume]).each do |phase|
      current = workflow(phase)
      triggers = current['on'] || current.fetch(true)
      assert triggers.dig('workflow_call', 'secrets', 'PIPELINE_GITHUB_TOKEN', 'required')
    end
    %w[code prove release].each do |phase|
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
          refute edit.include?('--add-label')
          assert_equal '@me', edit[edit.index('--add-assignee') + 1]
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
    refute steps('code').reject { |entry| entry['id'] == 'resolve' }.any? { |entry| entry.fetch('run', '').include?('gh workflow run prove.yml') }
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
    plan_resolve = run_step(step('plan', 'resolve'), scenario(['2-plan'], comments: ['# Think: scope']), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
    assert_equal 'false', plan_resolve.fetch('skip')
    plan_missing = run_step(step('plan', 'resolve'), scenario(['2-plan'], comments: []), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
    assert_equal 'true', plan_missing.fetch('skip')
    assert_equal [['workflow', 'run', 'think.yml', '-f', 'issue_number=42']], dispatches
    code_resolve = run_step(step('code', 'resolve'), scenario(['3-code'], comments: ['# Think: scope', '# Plan: steps']), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
    assert_equal 'false', code_resolve.fetch('skip')
    code_missing_plan = run_step(step('code', 'resolve'), scenario(['3-code'], comments: ['# Think: scope']), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
    assert_equal 'true', code_missing_plan.fetch('skip')
    assert_equal [['workflow', 'run', 'plan.yml', '-f', 'issue_number=42']], dispatches
    code_missing_think = run_step(step('code', 'resolve'), scenario(['4-release'], comments: []), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
    assert_equal 'true', code_missing_think.fetch('skip')
    assert_equal [['workflow', 'run', 'think.yml', '-f', 'issue_number=42']], dispatches
    prove_resolve = run_step(step('prove', 'resolve'), scenario(['4-release'], prs: [{ 'number' => 99, 'headRefName' => 'feature/issue-42-test', 'labels' => [] }], pr: { 'number' => 99, 'state' => 'OPEN', 'headRefName' => 'feature/issue-42-test', 'baseRefName' => 'main', 'body' => '- **Closes:** #42', 'title' => 'feat: test' }), { 'INPUT_ISSUE_NUMBER' => '42', 'INPUT_PR_NUMBER' => '', 'RUN_ID' => '' })
    assert_equal 'false', prove_resolve.fetch('skip')
  end

  def test_existing_pr_is_proven_only_for_release
    prs = [{ 'number' => 99, 'headRefName' => 'feature/issue-42-test', 'labels' => [] }]
    comments = ['# Think: scope', '# Plan: steps']
    %w[3-code 4-release].each do |label|
      output = run_step(step('think', 'resume'), scenario([label], comments: comments, prs: prs))
      assert_equal label == '4-release' ? 'prove' : 'code', output.fetch('resumed_stage')
      if label == '4-release'
        assert_equal [['workflow', 'run', 'prove.yml', '-f', 'pr_number=99', '-f', 'issue_number=42']], dispatches
      else
        assert_equal [['workflow', 'run', 'code.yml', '-f', 'issue_number=42']], dispatches
      end

      code_out = run_step(step('code', 'resolve'), scenario([label], comments: comments, prs: prs), { 'INPUT_ISSUE_NUMBER' => '42', 'RUN_ID' => '' })
      if label == '4-release'
        assert_equal 'true', code_out.fetch('skip')
        assert_equal [['workflow', 'run', 'prove.yml', '-f', 'pr_number=99', '-f', 'issue_number=42']], dispatches
      else
        assert_equal 'false', code_out.fetch('skip')
        assert_empty dispatches
        assert @calls.any? { |args| args.first(3) == ['pr', 'edit', '99'] && args.include?('--remove-assignee') && args.include?('@me') }
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
        'field' => { 'id' => 'STATUS', 'options' => %w[Think Plan Code Prove Release Done].map { |name| { 'name' => name, 'id' => name.downcase } } }
      }] } }
    } } }
  end

  def status_step(phase, status)
    steps(phase).find { |entry| entry.dig('env', 'TARGET_STATUS') == status } || raise("Missing #{status}")
  end

  def test_status_updates_use_the_expected_project_and_option
    { 'think' => 'Think', 'plan' => 'Plan', 'code' => 'Code', 'prove' => 'Prove' }.each do |phase, status|
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
    board['title'] = 'TEST BOARD.js'
    board['field']['options'].each { |option| option['name'] = option['name'].downcase }
    run_step(status_step('think', 'Think'), scenario([], project: data))
    assert @calls.any? { |args| args.include?('optionId=think') }
  end

  def test_paused_code_keeps_code_status_and_removes_trigger_labels
    status_entries = steps('code').select { |entry| entry.dig('env', 'TARGET_STATUS') }
    assert_equal ['Code'], status_entries.map { |entry| entry.dig('env', 'TARGET_STATUS') }
    run_step(status_entries.first, scenario(['3-code'], project: project))
    assert @calls.any? { |args| args.include?('optionId=code') }

    output = run_step(step('code', 'checkpoint'), scenario(['3-code'], project: project))
    assert_equal 'true', output.fetch('paused')
    edit = @calls.find { |args| args.first(2) == %w[issue edit] }
    refute edit.include?('--add-label')
    assert_equal '@me', edit[edit.index('--add-assignee') + 1]
    assert_equal LABELS + ['pause:code'], edit[edit.index('--remove-label') + 1].split(',')
    assert @calls.any? { |args| args.include?('optionId=code') }
  end

  def test_status_configuration_and_permission_errors_are_explicit
    PHASES.each do |phase|
      status = { 'think' => 'Think', 'plan' => 'Plan', 'code' => 'Code', 'prove' => 'Prove' }.fetch(phase)
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

  def run_prove_loop(control_failures: 0, review_failures: 0, record_failures: 0, success: true)
    entry = steps('prove').find { |item| item['name'] == 'Run Prove validation and auto-remediation loop' }.dup
    controls = <<~'BASH'
      run_deterministic_controls() {
        ROUND=$(( ${ROUND:-0} + 1 ))
        mkdir -p reports
        echo "checks:${ROUND}" >> "$RUNNER_TEMP/events"
        echo "exact check output round ${ROUND}" > gate-output.log
        [ "$ROUND" -gt "$TEST_CONTROL_FAILURES" ]
      }
      wait_for_pr_checks() {
        return 0
      }
    BASH
    entry['run'] = entry.fetch('run').sub(/run_deterministic_controls\(\) \{.*?\n\}/m, controls)
    mock = <<~'RUBY'
      count_path = File.join(ENV.fetch('RUNNER_TEMP'), 'fix-count')
      fixes = File.exist?(count_path) ? File.read(count_path).to_i : 0
      events = File.join(ENV.fetch('RUNNER_TEMP'), 'events')
      case File.basename($0)
      when 'git'
        puts "head-#{fixes}" if ARGV.first == 'rev-parse'
      when 'copilot'
        review = ARGV.include?('--agent=prove')
        File.open(events, 'a') { |f| f.puts(review ? 'review' : 'repair') }
        if review
          File.write('specs/issue-42/prove.md', "Independent review findings at head-#{fixes}")
        else
          report = File.read('reports/repair-attempt.md')
          File.write(File.join(ENV.fetch('RUNNER_TEMP'), "repair-#{fixes + 1}"), report)
          File.write(count_path, (fixes + 1).to_s)
        end
      when 'node'
        if ARGV.first.include?('validate-prove')
          review_path = File.join(ENV.fetch('RUNNER_TEMP'), 'review-count')
          reviews = File.exist?(review_path) ? File.read(review_path).to_i : 0
          File.write(review_path, (reviews + 1).to_s)
          if reviews < ENV.fetch('TEST_REVIEW_FAILURES').to_i
            warn 'Review verdict failed: missing acceptance criterion AC-2'
            exit 1
          end
        end
      end
    RUBY
    %w[copilot git node].each do |command|
      path = File.join(@directory, 'bin', command)
      File.write(path, "#!#{RbConfig.ruby}\n#{mock}")
      File.chmod(0o755, path)
    end
    status_script = status_step('prove', 'Prove').fetch('run').split("<<'STATUS_SCRIPT'\n", 2).last.split("\nSTATUS_SCRIPT", 2).first
    File.write(File.join(@directory, 'prove-project-status.sh'), status_script)
    File.write(File.join(@directory, 'record-prove.sh'), <<~'BASH')
      RECORD_COUNT=0
      if [ -f "$RUNNER_TEMP/record-count" ]; then
        RECORD_COUNT=$(cat "$RUNNER_TEMP/record-count")
      fi
      echo $((RECORD_COUNT + 1)) > "$RUNNER_TEMP/record-count"
      if [ "$RECORD_COUNT" -lt "$TEST_RECORD_FAILURES" ]; then
        echo "PR metadata failed: rollback evidence missing"
        exit 1
      fi
    BASH
    FileUtils.mkdir_p(File.join(@directory, 'specs/issue-42'))
    File.write(File.join(@directory, 'specs/issue-42/prove.md'), 'STALE REVIEW')
    data = scenario([], project: project, pr: { 'labels' => [] }, track_fix_labels: true)
    run_step(entry, data, {
      'BASE_REF' => 'main', 'BRANCH_NAME' => 'issue-42', 'FIX_LOOP_LIMIT' => '5',
      'TEST_CONTROL_FAILURES' => control_failures.to_s, 'TEST_REVIEW_FAILURES' => review_failures.to_s,
      'TEST_RECORD_FAILURES' => record_failures.to_s
    }, success: success)
    File.readlines(File.join(@directory, 'events'), chomp: true)
  end

  def test_failed_checks_skip_review_and_return_to_code_with_exact_context
    assert_equal %w[checks:1 repair checks:2 review], run_prove_loop(control_failures: 1)
    report = File.read(File.join(@directory, 'repair-1'))
    assert_includes report, 'exact check output round 1'
    assert_includes report, 'Independent review deferred'
    refute_includes report, 'STALE REVIEW'
    assert_includes report, 'specs/issue-42/plan.md'
    assert_includes report, 'head-0'
    %w[issue pr].each do |target|
      assert @calls.any? { |args| args.first(2) == [target, 'comment'] && args.include?('reports/repair-attempt.md') },
             "Repair report must persist on the #{target}"
    end
    statuses = @calls.flat_map { |args| args.grep(/^optionId=/) }
    assert_equal %w[optionId=code optionId=prove], statuses
  end

  def test_failed_review_is_given_to_code_and_checks_run_again_before_review
    assert_equal %w[checks:1 review repair checks:2 review], run_prove_loop(review_failures: 1)
    report = File.read(File.join(@directory, 'repair-1'))
    assert_includes report, 'Independent review findings at head-0'
    assert_includes report, 'Review verdict failed: missing acceptance criterion AC-2'
  end

  def test_five_repairs_stop_without_review_or_merge_when_checks_keep_failing
    events = run_prove_loop(control_failures: 10, success: false)
    assert_equal 5, events.count('repair')
    assert_equal 6, events.count { |event| event.start_with?('checks:') }
    refute_includes events, 'review'
    assert @calls.any? { |args| args.first(2) == %w[issue edit] && args.include?('needs:developer') }
    refute @calls.any? { |args| args.first(2) == %w[pr merge] }
    assert_equal 'optionId=code', @calls.flat_map { |args| args.grep(/^optionId=/) }.last
  end

  def test_final_pr_metadata_failure_also_returns_to_code_with_context
    assert_equal %w[checks:1 review repair checks:2 review], run_prove_loop(record_failures: 1)
    assert_includes File.read(File.join(@directory, 'repair-1')), 'PR metadata failed: rollback evidence missing'
  end

  def test_release_starts_only_after_validation_and_before_merge
    entries = steps('prove')
    validate = entries.index { |entry| entry['name'] == 'Run Prove validation and auto-remediation loop' }
    release = entries.index(status_step('prove', 'Release'))
    merge = entries.index { |entry| entry['name'] == 'Verify validated revisions and merge' }
    assert_operator release, :>, validate
    assert_operator release, :<, merge
    refute_match(/always\(|failure\(/, entries.fetch(release).fetch('if'))
    create = steps('code').find { |entry| entry.fetch('run', '').include?('gh pr create') }.fetch('run')
    assert_operator create.index('TARGET_STATUS=Prove'), :<, create.index('gh pr create')
  end

  def run_pr_checks(rollups, success: true)
    prove_entry = steps('prove').find { |entry| entry['name'] == 'Run Prove validation and auto-remediation loop' }
    script = prove_entry.fetch('run')
    function = script.match(/wait_for_pr_checks\(\) \{.*?\n\}/m)[0]
    sleep_path = File.join(@directory, 'bin/sleep')
    File.write(sleep_path, "#!#{RbConfig.ruby}\nexit 0\n")
    File.chmod(0o755, sleep_path)
    run_step(prove_entry.merge('run' => "#{function}\nwait_for_pr_checks\n"),
             scenario([], pr_sequence: rollups.map { |rollup| { 'statusCheckRollup' => rollup } }),
             { 'GITHUB_RUN_ID' => '123' }, success: success)
  end

  def test_pr_checks_wait_for_pending_ci_and_ignore_current_delivery_run
    own = { '__typename' => 'CheckRun', 'status' => 'IN_PROGRESS',
            'detailsUrl' => 'https://github.com/test/repo/actions/runs/123/job/456' }
    ci = { '__typename' => 'CheckRun', 'name' => 'test-and-build', 'status' => 'IN_PROGRESS',
           'detailsUrl' => 'https://github.com/test/repo/actions/runs/321/job/654' }
    run_pr_checks([[own, ci], [own, ci.merge('status' => 'COMPLETED', 'conclusion' => 'SUCCESS')]])
    assert_equal 2, @calls.count { |args| args.first(2) == %w[pr view] }
  end

  def test_failed_ci_and_external_status_block_independent_review
    [
      { '__typename' => 'CheckRun', 'status' => 'COMPLETED', 'conclusion' => 'FAILURE',
        'name' => 'tests', 'detailsUrl' => 'https://example.test/ci' },
      { '__typename' => 'StatusContext', 'state' => 'ERROR', 'context' => 'external CI',
        'targetUrl' => 'https://example.test/ci' }
    ].each do |check|
      run_pr_checks([[check]], success: false)
      assert_includes @stdout, 'GitHub PR checks failed'
      assert_includes @stdout, 'https://example.test/ci'
    end
  end

  def test_repositories_without_pr_checks_allow_registration_grace_period
    run_pr_checks([[], [], [], []])
    assert_equal 4, @calls.count { |args| args.first(2) == %w[pr view] }
  end

  def test_done_is_success_gated_and_after_release_preparation
    prove_entries = steps('prove')
    start_release = prove_entries.find { |entry| entry['id'] == 'start_release' }
    assert_operator prove_entries.index(start_release), :>, prove_entries.index { |entry| entry['name'].to_s.start_with?('Auto-release merged') }
    entries = steps('release')
    done = status_step('release', 'Done')
    refute_match(/always\(|failure\(/, done.fetch('if'))
    assert_operator entries.index(done), :>, entries.index { |entry| entry['id'] == 'release_completion' }
    assert_includes done.fetch('if'), "steps.release_completion.outcome == 'success'"
    run_step(done, scenario([], project: project))
    assert @calls.any? { |args| args.include?('optionId=done') }
  end

  def release_run(sha, event, status: 'completed', conclusion: 'success', id: 101, created: '2026-01-02T00:00:01Z')
    {
      'id' => id, 'head_sha' => sha, 'event' => event, 'status' => status,
      'conclusion' => conclusion, 'created_at' => created,
      'html_url' => "https://example.test/actions/runs/#{id}"
    }
  end

  def release_environment
    {
      'RELEASE_STARTED_AT' => '2026-01-02T00:00:00Z', 'RELEASE_MERGE_SHA' => 'merge-sha',
      'RELEASE_SHA' => '', 'RELEASE_TAG' => '', 'DEPLOYMENT_WORKFLOW' => '', 'DEPLOYMENT_PATHS' => '',
      'BASE_REF' => 'main', 'PROVE_BASE_SHA' => 'base-sha', 'GITHUB_REPOSITORY' => 'test-owner/test-repo',
      'GITHUB_SERVER_URL' => 'https://github.com', 'GITHUB_RUN_ID' => '123',
      'GITHUB_STEP_SUMMARY' => File.join(@directory, 'summary')
    }
  end

  def run_release_completion(runs, environment = {}, success: true, api_failure: false)
    %w[git sleep].each do |command|
      executable = File.join(@directory, 'bin', command)
      File.write(executable, "#!#{RbConfig.ruby}\nexit 0\n")
      File.chmod(0o755, executable)
    end
    entry = step('release', 'release_completion')
    data = scenario([], release_runs: runs, release_api_failure: api_failure)
    run_step(entry, data, release_environment.merge(environment), success: success)
    File.read(File.join(@directory, 'reports/release.md'))
  end

  def test_doomr_waits_for_exact_merge_deployment_not_an_unrelated_success
    wrong_sha = release_run('older-sha', 'push')
    wrong_event = release_run('merge-sha', 'workflow_dispatch', id: 102)
    stale = release_run('merge-sha', 'push', id: 103, created: '2026-01-01T00:00:00Z')
    pending = release_run('merge-sha', 'push', id: 104, status: 'in_progress', conclusion: nil)
    success = pending.merge('status' => 'completed', 'conclusion' => 'success')
    report = run_release_completion(
      { 'deploy-pages.yml' => [[wrong_sha, wrong_event, stale], [pending], [success]] },
      { 'DEPLOYMENT_WORKFLOW' => 'deploy-pages.yml' }
    )
    assert_includes report, 'https://example.test/actions/runs/104'
    assert_includes report, 'All required release workflows succeeded'
    polls = @calls.select { |args| args.first == 'api' }
    assert_equal 3, polls.length
    assert polls.all? { |args| args[1].include?('head_sha=merge-sha') }
    assert_empty dispatches
    %w[issue pr].each do |target|
      assert @calls.any? { |args| args.first(2) == [target, 'comment'] && args.include?('reports/release.md') }
    end
  end

  def test_library_waits_for_npm_and_documentation_at_release_revision
    report = run_release_completion({
      'publish-npm.yml' => [[release_run('release-sha', 'release')]],
      'deploy-docs.yml' => [[release_run('release-sha', 'push', id: 102)]]
    }, { 'RELEASE_SHA' => 'release-sha', 'RELEASE_TAG' => 'v1.2.3', 'DEPLOYMENT_WORKFLOW' => 'deploy-docs.yml' })
    assert_includes report, 'GitHub Release: v1.2.3'
    assert_includes report, 'publish-npm.yml'
    assert_includes report, 'deploy-docs.yml'
    assert_includes report, 'All required release workflows succeeded'
    assert_equal 2, @calls.count { |args| args.first == 'api' }
  end

  def test_failed_cancelled_or_skipped_release_does_not_pass
    %w[failure cancelled skipped timed_out action_required].each do |conclusion|
      report = run_release_completion(
        { 'publish-npm.yml' => [[release_run('release-sha', 'release', conclusion: conclusion)]] },
        { 'RELEASE_SHA' => 'release-sha', 'RELEASE_TAG' => 'v1.2.3' }, success: false
      )
      assert_includes report, conclusion
      assert_includes report, 'Issue stays in Release'
      assert_includes report, 'https://example.test/actions/runs/101'
      refute_includes report, 'All required release workflows succeeded'
    end
  end

  def test_successful_npm_publish_does_not_hide_failed_documentation_deployment
    report = run_release_completion({
      'publish-npm.yml' => [[release_run('release-sha', 'release')]],
      'deploy-docs.yml' => [[release_run('release-sha', 'push', id: 102, conclusion: 'failure')]]
    }, { 'RELEASE_SHA' => 'release-sha', 'RELEASE_TAG' => 'v1.2.3', 'DEPLOYMENT_WORKFLOW' => 'deploy-docs.yml' },
                                       success: false)
    assert_includes report, 'publish-npm.yml, run 101: https://example.test/actions/runs/101 — success'
    assert_includes report, 'deploy-docs.yml, run 102: https://example.test/actions/runs/102 — failure'
    assert_includes report, 'Issue stays in Release'
  end

  def test_release_revision_and_reports_are_persisted
    release = step('prove', 'release').fetch('run')
    assert_includes release, '--target "$RELEASE_COMMIT"'
    assert_includes release, 'echo "release_sha=${RELEASE_COMMIT}" >> "$GITHUB_OUTPUT"'
    artifact = steps('prove').find { |entry| entry.dig('with', 'name') == 'prove-spec' }
    assert_includes artifact.dig('with', 'path'), 'reports/release.md'
    assert_includes artifact.fetch('if'), 'always()'
    release_artifact = steps('release').find { |entry| entry['uses'].to_s.start_with?('actions/upload-artifact@') }
    assert_includes release_artifact.dig('with', 'path'), 'reports/release.md'
    assert_includes release_artifact.fetch('if'), 'always()'
  end

  def test_missing_release_run_times_out_instead_of_marking_done
    report = run_release_completion(
      { 'deploy-pages.yml' => [[]] }, { 'DEPLOYMENT_WORKFLOW' => 'deploy-pages.yml' }, success: false
    )
    assert_includes report, 'Timed out'
    assert_includes report, 'Last run: not created'
    assert_equal 120, @calls.count { |args| args.first == 'api' }
  end

  def test_release_api_failure_is_explicit_and_reported
    report = run_release_completion({}, { 'DEPLOYMENT_WORKFLOW' => 'deploy-pages.yml' },
                                    success: false, api_failure: true)
    assert_includes report, 'Could not read deploy-pages.yml'
    assert_includes @stdout, '::error::'
    assert @calls.any? { |args| args.first(2) == %w[issue comment] }
  end

  def test_merge_only_repositories_complete_without_waiting_for_nonexistent_workflows
    report = run_release_completion({})
    assert_includes report, 'no external publication/deployment was applicable'
    refute @calls.any? { |args| args.first == 'api' }

    status_script = status_step('prove', 'Prove').fetch('run').split("<<'STATUS_SCRIPT'\n", 2).last.split("\nSTATUS_SCRIPT", 2).first
    File.write(File.join(@directory, 'prove-project-status.sh'), status_script)
    start_release = step('prove', 'start_release')
    output = run_step(start_release, scenario([], project: project), release_environment)
    assert_equal 'false', output.fetch('dispatched')
    assert @calls.any? { |args| args.include?('optionId=done') }
  end

  def test_release_failure_keeps_status_and_posts_durable_failure_links
    status_script = status_step('prove', 'Prove').fetch('run').split("<<'STATUS_SCRIPT'\n", 2).last.split("\nSTATUS_SCRIPT", 2).first
    File.write(File.join(@directory, 'prove-project-status.sh'), status_script)
    entry = steps('prove').find { |item| item['name'] == 'Report Release failure on the issue and PR' }
    assert_includes entry.fetch('if'), 'failure()'
    assert_includes entry.fetch('if'), "steps.release_stage.outcome == 'success'"
    run_step(entry, scenario([], project: project), release_environment)
    assert @calls.any? { |args| args.include?('optionId=release') }
    %w[issue pr].each do |target|
      assert @calls.any? { |args| args.first(2) == [target, 'comment'] && args.last.include?('actions/runs/123') }
    end
    marker = steps('prove').find { |item| item['name'] == 'Mark issue needs:developer if Prove failed' }
    run_step(marker, scenario)
    assert @calls.any? { |args| args.first(2) == %w[issue edit] && args.include?('needs:developer') }
  end

  def test_documentation_path_gate_uses_real_git_and_selects_the_triggering_push
    prepare_stale_pr
    run_freshness_script('Refresh PR branch against latest base')
    FileUtils.mkdir_p(File.join(@repository, 'src'))
    File.write(File.join(@repository, 'src/library.js'), 'export const value = 1;')
    git_command('add', '.')
    git_command('commit', '-m', 'Library implementation')
    merge_sha = git_command('rev-parse', 'HEAD')
    File.write(File.join(@repository, 'CHANGELOG.md'), 'New release')
    git_command('add', '.')
    git_command('commit', '-m', 'Release metadata only')
    release_sha = git_command('rev-parse', 'HEAD')
    environment = release_environment.merge(
      'RELEASE_MERGE_SHA' => merge_sha, 'RELEASE_SHA' => release_sha, 'RELEASE_TAG' => 'v1.2.3',
      'DEPLOYMENT_WORKFLOW' => 'deploy-docs.yml', 'DEPLOYMENT_PATHS' => "website/\nsrc/\n.github/workflows/deploy-docs.yml",
      'PROVE_BASE_SHA' => @base_sha
    )
    data = scenario([], release_runs: {
      'publish-npm.yml' => [[release_run(release_sha, 'release')]],
      'deploy-docs.yml' => [[release_run(merge_sha, 'push')]]
    })
    run_freshness_script('Wait for publication and deployment before Done', data: data, **environment.transform_keys(&:to_sym))
    assert @calls.any? { |args| args.first == 'api' && args[1].include?("deploy-docs.yml/runs?event=push&head_sha=#{merge_sha}") }

    FileUtils.mkdir_p(File.join(@repository, 'website'))
    File.write(File.join(@repository, 'website/package.json'), '{"version":"1.2.3"}')
    git_command('add', '.')
    git_command('commit', '-m', 'Release website metadata')
    release_sha = git_command('rev-parse', 'HEAD')
    data['release_runs'] = {
      'publish-npm.yml' => [[release_run(release_sha, 'release')]],
      'deploy-docs.yml' => [[release_run(release_sha, 'push')]]
    }
    run_freshness_script('Wait for publication and deployment before Done', data: data,
                         **environment.merge('RELEASE_SHA' => release_sha).transform_keys(&:to_sym))
    assert @calls.any? { |args| args.first == 'api' && args[1].include?("deploy-docs.yml/runs?event=push&head_sha=#{release_sha}") }
  end

  def test_documentation_is_not_awaited_when_neither_push_matches_its_paths
    prepare_stale_pr
    run_freshness_script('Refresh PR branch against latest base')
    merge_sha = git_command('rev-parse', 'HEAD')
    environment = release_environment.merge(
      'RELEASE_MERGE_SHA' => merge_sha, 'PROVE_BASE_SHA' => @base_sha,
      'DEPLOYMENT_WORKFLOW' => 'deploy-docs.yml', 'DEPLOYMENT_PATHS' => "website/\nsrc/\n.github/workflows/deploy-docs.yml"
    )
    run_freshness_script('Wait for publication and deployment before Done', data: scenario, **environment.transform_keys(&:to_sym))
    refute @calls.any? { |args| args.first == 'api' }
    assert_includes File.read(File.join(@repository, 'reports/release.md')), 'Deployment not applicable'
  end

  def test_autonomous_decision_validation_is_installed_for_think
    install = steps('think').find { |entry| entry['name'] == 'Install ALTEN-group/coding-pal think primitives' }.fetch('run')
    assert_includes install, 'cp -R /tmp/alten-coding-pal/skills/decision-record .agents/skills/decision-record'
    assert_includes install, 'cp /tmp/alten-coding-pal/instructions/decision-record.instructions.md .github/instructions/'
  end

  def test_high_risk_automated_metadata_is_checked_before_merge
    script = steps('prove').find { |entry| entry['name'] == 'Prepare automated validation recording' }.fetch('run')
    assert_includes script, 'readPlan, readThink'
    assert_includes script, 'if [ "$TIER" = "High" ] || [ "$TIER" = "Critical" ]'
    assert_includes script, "only when concrete rollback verification evidence is recorded"
    assert_includes script, "leave the affected field Pending"
    assert_operator script.index('--stage pass'), :<, script.index('copilot --model="auto" --agent="prove"')
    assert_operator script.index('copilot --model="auto" --agent="prove"'), :<, script.index('--stage prove')
    entries = steps('prove')
    merge = entries.find { |entry| entry['name'] == 'Verify validated revisions and merge' }
    assert_operator entries.index(merge), :>, entries.index { |entry| entry['name'] == 'Run Prove validation and auto-remediation loop' }
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
    entry = (steps('prove') + steps('release')).find { |item| item['name'] == name }
    File.write(@environment.fetch('TEST_SCENARIO'), JSON.generate(data))
    File.write(@environment.fetch('TEST_CALLS'), '')
    File.write(@environment.fetch('TEST_VIOLATIONS'), '')
    declared = resolve_step_environment(entry)
    env = @environment.merge(declared).merge(
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

  def test_code_creates_branch_from_latest_remote_base_not_stale_checkout
    prepare_stale_pr
    old_base = git_command('rev-parse', 'main~1')
    git_command('checkout', '--detach', old_base)
    git_command('update-ref', 'refs/remotes/origin/main', old_base)
    specs = File.join(@repository, 'specs/issue-42')
    FileUtils.mkdir_p(specs)
    File.write(File.join(specs, 'think.md'), "# Think: test\n")
    File.write(File.join(specs, 'plan.md'), "# Plan: test\n")
    File.write(@environment.fetch('TEST_SCENARIO'), JSON.generate(scenario.merge('issue' => { 'title' => 'Fresh branch' })))
    File.write(@environment.fetch('TEST_CALLS'), '')
    File.write(@environment.fetch('TEST_VIOLATIONS'), '')
    entry = steps('code').find { |item| item['name'] == 'Prepare implementation branch and commit specs' }
    environment = @environment.merge(resolve_step_environment(entry)).merge(
      'PATH' => "#{@environment.fetch('PATH')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      'BASE_REF' => 'main'
    )
    output, error, status = Open3.capture3(
      environment, 'bash', '--noprofile', '--norc', '-eo', 'pipefail',
      stdin_data: entry.fetch('run'), chdir: @repository, unsetenv_others: true
    )
    assert status.success?, "#{output}\n#{error}"
    assert_equal '', File.read(@environment.fetch('TEST_VIOLATIONS'))
    assert_equal 'feature/issue-42-fresh-branch', git_command('branch', '--show-current')
    assert_equal @base_sha, git_command('rev-parse', 'HEAD')
    assert_equal "updated base\n", File.read(File.join(@repository, 'shared.txt'))
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
    run_freshness_script(name, data: scenario(pr: { 'headRefOid' => head, 'mergeCommit' => { 'oid' => 'merged-sha' } }), PROVE_BASE_SHA: @base_sha)
    assert_includes @calls, ['pr', 'merge', '99', '--squash', '--delete-branch', '--match-head-commit', head]
    assert_includes File.read(@environment.fetch('GITHUB_ENV')), 'RELEASE_MERGE_SHA=merged-sha'
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
    def test_all_deployment_callers_track_completion_with_matching_push_filters
      root = ENV.fetch('PROJECT_WORKFLOWS_ROOT')
      Dir.glob(File.join(root, '*/.github/workflows/code.yml')).each do |code_path|
        directory = File.dirname(code_path)
        %w[code prove].each do |phase|
          current = YAML.load_file(File.join(directory, "#{phase}.yml"))
          settings = current.fetch('jobs').fetch('prove').fetch('with')
          deployment = Dir.glob(File.join(directory, 'deploy-*.yml'))
          assert_operator deployment.length, :<=, 1
          if deployment.empty?
            refute settings.key?('deployment_workflow'), code_path
            next
          end
          filename = File.basename(deployment.first)
          assert_equal filename, settings.fetch('deployment_workflow'), code_path
          workflow = YAML.load_file(deployment.first)
          triggers = workflow['on'] || workflow.fetch(true)
          push = triggers.fetch('push')
          expected = settings.fetch('deployment_paths', '').lines.map(&:strip).reject(&:empty?)
          paths = push.fetch('paths', []).map { |path| path.delete_suffix('**') }
          assert_equal paths, expected, code_path
        end
      end
    end

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
        assert_equal ['1-think'], labels, repository
        expected = "github.event_name == 'workflow_dispatch' || " \
                   "(github.event_name == 'issues' && github.event.issue.state == 'open' && " \
                   "github.event.label.name == '1-think')"
        assert_equal expected, job.fetch('if').split.join(' '), repository
        assert_equal title, job.fetch('with').fetch('project_title')
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-think.yml@main', job.fetch('uses')
        %w[plan code prove].each do |phase|
          current = YAML.load_file(File.join(directory, "#{phase}.yml"))
          job = current.fetch('jobs').fetch(phase)
          assert_equal 'inherit', job.fetch('secrets'), repository
          events = current['on'] || current.fetch(true)
          if %w[plan code].include?(phase)
            assert_equal %w[issues workflow_dispatch], events.keys, "#{repository} #{phase}.yml"
            assert_equal ['labeled'], events.fetch('issues').fetch('types'), "#{repository} #{phase}.yml"
            assert_equal "${{ inputs.issue_number || github.event.issue.number || '' }}", job.fetch('with').fetch('issue_number')
            phase_labels = job.fetch('if').scan(/github.event.label.name == '([^']+)'/).flatten
            assert_equal phase == 'plan' ? ['2-plan'] : %w[3-code 4-release], phase_labels, "#{repository} #{phase}.yml"
          else
            assert_equal ['workflow_dispatch'], events.keys, repository
            refute job.key?('if'), repository
          end
          inputs = events.fetch('workflow_dispatch').fetch('inputs')
          assert_equal false, inputs.fetch('workflow_run_id').fetch('required')
          assert_equal false, inputs.fetch('issue_number').fetch('required')
          assert_equal "${{ inputs.workflow_run_id || '' }}", job.fetch('with').fetch('workflow_run_id')
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
        prove_wrapper = YAML.load_file(File.join(directory, 'prove.yml'))
        expected_npm_release = %w[BumpR.js GroovR.js LoopR.js RoostR.js Spock.js].include?(repository)
        prove = code.fetch('jobs').fetch('prove')
        assert_equal 'code', prove.fetch('needs')
        assert_equal "needs.code.outputs.continue_to_prove == 'true'", prove.fetch('if')
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-prove.yml@main', prove.fetch('uses')
        assert_equal '${{ github.run_id }}', prove.dig('with', 'workflow_run_id')
        assert_equal title, prove.dig('with', 'project_title')
        assert_equal 'inherit', prove.fetch('secrets')
        assert_equal expected_npm_release, prove.dig('with', 'auto_release_npm'), "#{repository} code.yml"
        assert_equal expected_npm_release, prove_wrapper.dig('jobs', 'prove', 'with', 'auto_release_npm'), "#{repository} prove.yml"
        audits = YAML.load_file(File.join(directory, 'audits.yml'))
        assert_equal 'Audit - Run audit', audits.fetch('name')
        resume = YAML.load_file(File.join(directory, 'upstream-resume.yml'))
        assert_equal 'Pipeline - Resume upstream', resume.fetch('name'), "#{repository} upstream-resume.yml"
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-upstream-resume.yml@main',
                     resume.dig('jobs', 'resume', 'uses'), "#{repository} upstream-resume.yml"
        release_wrapper = YAML.load_file(File.join(directory, 'release.yml'))
        assert_equal 'Pipeline - Release', release_wrapper.fetch('name'), "#{repository} release.yml"
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-release.yml@main',
                     release_wrapper.dig('jobs', 'release', 'uses'), "#{repository} release.yml"
        refute release_wrapper.key?('concurrency'), "#{repository} release.yml must not share the delivery concurrency lock"
      end
    end
  end

  def test_scope_guard_extracts_in_scope_from_file_scope_and_boundaries
    plan_md = <<~MARKDOWN
      # Plan: Secret Room Door SFX

      ## File Scope & Boundaries
      - **In Scope:** `src/levels/door.ts`, `tests/door.test.ts`
      - **Out of Scope:** `src/audio/engine.ts`
      - **Irreversible Changes:** _None._
    MARKDOWN
    plan_file = File.join(@directory, 'plan.md')
    File.write(plan_file, plan_md)
    [
      steps('prove').find { |item| item['name'] == 'Run Prove validation and auto-remediation loop' }.fetch('run')
    ].each do |script|
      snippet = script[/node -e '\s*(const fs = require\("fs"\);.*?)' "\$\{SPEC_DIR\}\/plan\.md"/m, 1]
      refute_nil snippet
      out, status = Open3.capture2('node', '-e', snippet, plan_file)
      assert status.success?
      assert_equal %w[src/levels/door.ts tests/door.test.ts], out.lines.map(&:strip).reject(&:empty?)
    end
  end

  def test_companion_editor_dispatch_supports_think_schema_and_body_fallback
    entry = steps('prove').find { |item| item['name'] == 'Dispatch companion game editor updates after PR merge' }
    FileUtils.mkdir_p(File.join(@directory, 'specs/issue-42'))
    File.write(File.join(@directory, 'specs/issue-42/editor-requests.json'), JSON.generate([
      {
        'editor' => 'mappr',
        'repo' => '1pizzateam/MappR',
        'title' => 'feat(doors): support secret door SFX trigger property',
        'problem' => 'DoomR.js moved secret room SFX to door open state.',
        'suggestedDirection' => 'Update src/inspector/DoorInspector.ts',
        'affectedFiles' => ['src/levels/door.ts']
      }
    ]))
    run_step(entry, scenario, { 'REPO_FULL_NAME' => '1pizzateam/DoomR.js', 'REPO_NAME' => 'DoomR.js', 'BASE_REF' => 'main' })
    create_call = @calls.find { |args| args.first(2) == %w[issue create] }
    refute_nil create_call
    assert_includes create_call, '1pizzateam/MappR'
    body_arg = create_call[create_call.index('--body') + 1]
    assert_includes body_arg, '## Problem'
    assert_includes body_arg, 'DoomR.js moved secret room SFX to door open state.'
    assert_includes body_arg, '## Suggested Direction'
    assert_includes body_arg, 'src/levels/door.ts'
  end

  def test_upstream_resume_unblocks_matching_issues_via_jq_pipe
    %w[npm seq grep sort].each do |command|
      if command == 'npm'
        path = File.join(@directory, 'bin/npm')
        File.write(path, "#!#{RbConfig.ruby}\nputs '1.2.3'\n")
        File.chmod(0o755, path)
      else
        executable = ENV.fetch('PATH').split(File::PATH_SEPARATOR)
                        .map { |dir| File.join(dir, command) }
                        .find { |candidate| File.executable?(candidate) && !File.directory?(candidate) }
        File.symlink(executable, File.join(@directory, 'bin', command)) unless File.exist?(File.join(@directory, 'bin', command))
      end
    end
    entry = workflow('upstream-resume').fetch('jobs').fetch('resume').fetch('steps').first
    issues = [
      { 'number' => 12, 'body' => 'Waiting on @1pizzateam/spock release', 'comments' => [] },
      { 'number' => 19, 'body' => 'Unrelated issue', 'comments' => [{ 'body' => 'Blocked on @1pizzateam/roostr' }] }
    ]
    run_step(entry, scenario([], issues: issues))
    edits = @calls.select { |args| args.first(2) == %w[issue edit] }
    assert_equal [['issue', 'edit', '12', '--remove-label', 'blocked:upstream', '--add-label', '4-release']], edits
  end

  def test_developer_comments_and_previous_specs_are_passed_to_agents
    copilot_args_file = File.join(@directory, 'copilot_args.json')
    copilot_bin = File.join(@directory, 'bin/copilot')
    File.write(copilot_bin, "#!#{RbConfig.ruby}\nrequire 'json'\nFile.write(#{copilot_args_file.inspect}, JSON.generate(ARGV))\n")
    File.chmod(0o755, copilot_bin)
    printf_exec = ENV.fetch('PATH').split(File::PATH_SEPARATOR)
                     .map { |dir| File.join(dir, 'printf') }
                     .find { |candidate| File.executable?(candidate) && !File.directory?(candidate) }
    File.symlink(printf_exec, File.join(@directory, 'bin/printf')) if printf_exec && !File.exist?(File.join(@directory, 'bin/printf'))

    comments = [
      '# Think: initial think spec',
      '⏸️ **Paused after Think for Manual Validation**',
      '# Plan: initial plan spec',
      'Pull request opened for #42: https://example.test/pr/99',
      'Please play the secret SFX when the door starts opening instead of on room entry.'
    ]
    data = scenario(['1-think'], comments: comments, prs: [{ 'number' => 99, 'headRefName' => 'feature/issue-42-test', 'labels' => [] }])
    data['issue']['title'] = 'Secret door SFX timing'

    think_step = steps('think').find { |item| item['name'] == 'Fetch issue context and run Thinker agent' }
    run_step(think_step, data)
    think_prompt = JSON.parse(File.read(copilot_args_file)).last
    assert_includes think_prompt, '# Think: initial think spec'
    assert_includes think_prompt, 'Please play the secret SFX when the door starts opening instead of on room entry.'
    refute_includes think_prompt, 'Paused after Think for Manual Validation'
    refute_includes think_prompt, 'Pull request opened for #42'

    plan_step = steps('plan').find { |item| item['name'] == 'Fetch issue context and run Planner agent' }
    run_step(plan_step, data)
    plan_prompt = JSON.parse(File.read(copilot_args_file)).last
    assert_includes plan_prompt, '# Plan: initial plan spec'
    assert_includes plan_prompt, 'Please play the secret SFX when the door starts opening instead of on room entry.'
    refute_includes plan_prompt, 'Paused after Think for Manual Validation'

    code_step = steps('code').find { |item| item['name'] == 'Run Code Agent to implement plan.md and prepare pr-body.md' }
    run_step(code_step, data, { 'BRANCH_NAME' => 'feature/issue-42-test', 'BASE_REF' => 'main' })
    code_prompt = JSON.parse(File.read(copilot_args_file)).last
    assert_includes code_prompt, 'Please play the secret SFX when the door starts opening instead of on room entry.'
    refute_includes code_prompt, 'Paused after Think for Manual Validation'
  end

  def test_ai_cost_footers_are_appended_and_stripped_when_restoring_specs
    copilot_bin = File.join(@directory, 'bin/copilot')
    session_dir = File.join(@directory, '.copilot/session-state/s1')
    File.write(copilot_bin, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'fileutils'
      require 'json'
      dir = #{session_dir.inspect}
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'events.jsonl'), [
        JSON.generate({ 'type' => 'assistant.usage', 'model' => 'claude-sonnet-4.5', 'input_tokens' => 10_000, 'output_tokens' => 2_000 }),
        JSON.generate({ 'type' => 'assistant.usage', 'model' => 'claude-sonnet-4.5', 'input_tokens' => 5_000, 'output_tokens' => 1_000 })
      ].join("\\n") + "\\n")
    RUBY
    File.chmod(0o755, copilot_bin)

    data = scenario(['1-think'])
    data['issue']['title'] = 'Track AI cost per pipeline step'
    FileUtils.mkdir_p(File.join(@directory, 'specs/issue-42'))
    File.write(File.join(@directory, 'specs/issue-42/think.md'), "# Think: Track AI cost\n\n## Problem\nCost visibility.")

    think_agent_step = steps('think').find { |item| item['name'] == 'Fetch issue context and run Thinker agent' }
    run_step(think_agent_step, data)
    assert File.file?(File.join(@directory, 'specs/issue-42/ai-cost-step.md'))

    think_comment_step = steps('think').find { |item| item['name'] == 'Comment think.md on issue' }
    run_step(think_comment_step, data)
    comment_call = @calls.find { |args| args.first(2) == %w[issue comment] }
    refute_nil comment_call
    posted_think = File.read(comment_call[comment_call.index('--body-file') + 1])
    assert_includes posted_think, "# Think: Track AI cost\n\n## Problem\nCost visibility."
    assert_includes posted_think, '<!-- ai-cost-step:{"step":"Think","model":"claude-sonnet-4.5","input_tokens":15000,"output_tokens":3000,"cached_tokens":0,"requests":2,"cost_usd":0.09} -->'
    assert_includes posted_think, '💰 **AI Cost (Think):** `$0.0900` (`claude-sonnet-4.5` · 15000 in / 3000 out tokens · 2 requests)'
    refute_includes File.read(File.join(@directory, 'specs/issue-42/think.md')), 'ai-cost-step'

    plan_data = scenario(['2-plan'], comments: [posted_think])
    plan_data['issue']['title'] = 'Track AI cost per pipeline step'
    FileUtils.rm_rf(File.join(@directory, 'specs/issue-42'))
    run_step(step('plan', 'resolve'), plan_data)
    restored_think = File.read('/tmp/specs/issue-42/think.md')
    assert_equal "# Think: Track AI cost\n\n## Problem\nCost visibility.\n", restored_think
    refute_includes restored_think, 'ai-cost-step'

    FileUtils.mkdir_p(File.join(@directory, 'specs/issue-42'))
    File.write(File.join(@directory, 'specs/issue-42/think.md'), restored_think)
    File.write(File.join(@directory, 'specs/issue-42/plan.md'), "# Plan: Track AI cost\n\n## Steps\n1. Add cost footer.")
    plan_agent_step = steps('plan').find { |item| item['name'] == 'Fetch issue context and run Planner agent' }
    run_step(plan_agent_step, plan_data)
    plan_comment_step = steps('plan').find { |item| item['name'] == 'Comment plan.md on issue' }
    run_step(plan_comment_step, plan_data)
    plan_comment_call = @calls.find { |args| args.first(2) == %w[issue comment] }
    posted_plan = File.read(plan_comment_call[plan_comment_call.index('--body-file') + 1])
    assert_includes posted_plan, '💰 **AI Cost (Plan):** `$0.0900` (`claude-sonnet-4.5` · 15000 in / 3000 out tokens · 2 requests · **Cumulative:** `$0.1800`)'
    refute_includes File.read(File.join(@directory, 'specs/issue-42/plan.md')), 'ai-cost-step'
  ensure
    FileUtils.rm_rf('/tmp/specs/issue-42')
  end

  def test_release_report_includes_cumulative_ai_cost_summary_table
    comments = [
      "# Think: Spec\n\n---\n<!-- ai-cost-step:{\"step\":\"Think\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":10000,\"output_tokens\":2000,\"cached_tokens\":0,\"requests\":2,\"cost_usd\":0.06} -->\n💰 **AI Cost (Think):** `$0.0600`",
      "# Plan: Spec\n\n---\n<!-- ai-cost-step:{\"step\":\"Plan\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":20000,\"output_tokens\":4000,\"cached_tokens\":0,\"requests\":3,\"cost_usd\":0.12} -->\n💰 **AI Cost (Plan):** `$0.1200`",
      "Pull request opened for #42: https://example.test/pr/99\n\n---\n<!-- ai-cost-step:{\"step\":\"Code\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":50000,\"output_tokens\":10000,\"cached_tokens\":0,\"requests\":8,\"cost_usd\":0.3} -->\n💰 **AI Cost (Code):** `$0.3000`",
      "# Prove: Spec\n\n---\n<!-- ai-cost-step:{\"step\":\"Prove\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":15000,\"output_tokens\":1000,\"cached_tokens\":0,\"requests\":2,\"cost_usd\":0.06} -->\n💰 **AI Cost (Prove):** `$0.0600`"
    ]
    status_script = status_step('prove', 'Prove').fetch('run').split("<<'STATUS_SCRIPT'\n", 2).last.split("\nSTATUS_SCRIPT", 2).first
    File.write(File.join(@directory, 'prove-project-status.sh'), status_script)
    data = scenario(['4-release'], comments: comments, project: project)
    run_step(step('prove', 'start_release'), data, { 'RELEASE_MERGE_SHA' => 'merge-sha' })
    report = File.read(File.join(@directory, 'reports/release.md'))
    assert_includes report, '## AI Cost Summary'
    assert_includes report, '| Think | `claude-sonnet-4.5` | 10000 | 2000 | 2 | `$0.0600` |'
    assert_includes report, '| Plan | `claude-sonnet-4.5` | 20000 | 4000 | 3 | `$0.1200` |'
    assert_includes report, '| Code | `claude-sonnet-4.5` | 50000 | 10000 | 8 | `$0.3000` |'
    assert_includes report, '| Prove | `claude-sonnet-4.5` | 15000 | 1000 | 2 | `$0.0600` |'
    assert_includes report, '| **Total** | — | **95000** | **17000** | **15** | **`$0.5400`** |'
  end

  def test_project_board_syncs_cumulative_ai_cost_custom_field
    %w[think plan code prove release].each do |workflow|
      refute_includes File.read(File.join(ROOT, ".github/workflows/pipeline-#{workflow}.yml")), 'field(name: "AI Cost")',
        "pipeline-#{workflow}.yml must not use field(name: \"AI Cost\") which throws a GraphQL error when a project lacks the AI Cost field"
    end

    comments = [
      "# Think: Spec\n\n---\n<!-- ai-cost-step:{\"step\":\"Think\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":10000,\"output_tokens\":2000,\"cached_tokens\":0,\"requests\":2,\"cost_usd\":0.06} -->",
      "# Plan: Spec\n\n---\n<!-- ai-cost-step:{\"step\":\"Plan\",\"model\":\"claude-sonnet-4.5\",\"input_tokens\":20000,\"output_tokens\":4000,\"cached_tokens\":0,\"requests\":3,\"cost_usd\":0.12} -->"
    ]
    proj_num = project
    proj_num['data']['repository']['owner']['projectsV2']['nodes'].first['fields'] = {
      'nodes' => [{}, { 'id' => 'COST_NUM', 'name' => 'AI Cost', 'dataType' => 'NUMBER' }]
    }
    run_step(status_step('code', 'Code'), scenario(['4-release'], comments: comments, project: proj_num))
    cost_mutation = @calls.find { |args| args.include?('fieldId=COST_NUM') }
    refute_nil cost_mutation
    assert_includes cost_mutation, 'val=0.18'

    proj_text = project
    proj_text['data']['repository']['owner']['projectsV2']['nodes'].first['fields'] = {
      'nodes' => [{ 'id' => 'COST_TXT', 'name' => 'AI Cost', 'dataType' => 'TEXT' }]
    }
    run_step(status_step('release', 'Done'), scenario(['4-release'], comments: comments, project: proj_text))
    text_mutation = @calls.find { |args| args.include?('fieldId=COST_TXT') }
    refute_nil text_mutation
    assert_includes text_mutation, 'val=$0.1800'
  end
end
