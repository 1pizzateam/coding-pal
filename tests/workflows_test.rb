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
    %w[queued resumed_stage].each { |output| assert_includes gate, "steps.fifo.outputs.#{output}" }
  end

  def test_smart_resume_reuses_specs
    fifo = step('think', 'fifo')
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
      output = run_step(step('think', 'fifo'), scenario([label], prs: prs))
      assert_equal label == '4-release' ? 'prove' : 'code', output.fetch('resumed_stage')
      if label == '4-release'
        assert_equal [['workflow', 'run', 'prove.yml', '-f', 'pr_number=99', '-f', 'issue_number=42']], dispatches
      else
        assert_empty dispatches
        assert @calls.any? { |args| args.first(3) == ['pr', 'edit', '99'] && args.include?('review:code') }
      end
    end
  end

  def test_busy_pipeline_queues_without_dispatching
    data = scenario(['3-code'], runs: [{ 'status' => 'in_progress' }])
    assert_equal 'true', run_step(step('think', 'fifo'), data).fetch('queued')
    assert_empty dispatches
    refute @calls.any? { |args| args.first(2) == %w[issue edit] }
  end

  def test_active_pr_blocks_but_review_pr_does_not
    prs = [{ 'number' => 100, 'headRefName' => 'feature/issue-7-work', 'labels' => [] }]
    assert_equal 'true', run_step(step('think', 'fifo'), scenario(['3-code'], prs: prs)).fetch('queued')
    prs.first['labels'] = [{ 'name' => 'review:code' }]
    assert_equal 'false', run_step(step('think', 'fifo'), scenario(['3-code'], prs: prs)).fetch('queued')
  end

  def test_all_numbered_labels_participate_in_fifo
    LABELS.each do |label|
      data = scenario(['4-release'], queue: [queue_issue(7, [label])])
      assert_equal 'true', run_step(step('think', 'fifo'), data).fetch('queued')
    end
    data = scenario(['4-release'], queue: [queue_issue(7, ['ready']), queue_issue(8, ['3-code', 'needs:developer'])])
    assert_equal 'false', run_step(step('think', 'fifo'), data).fetch('queued')
  end

  def test_queue_advancement_orders_by_label_time_then_issue_number
    queue = [
      queue_issue(42, ['3-code'], '2026-01-01T00:00:00Z'),
      queue_issue(2, ['1-think', 'needs:developer'], '2026-01-01T00:00:00Z'),
      queue_issue(3, ['ready'], '2026-01-01T00:00:00Z'),
      queue_issue(9, ['2-plan'], '2026-01-03T00:00:00Z'),
      queue_issue(8, ['4-release']), queue_issue(7, ['3-code'])
    ]
    %w[think plan code].each do |phase|
      run_step(step(phase, 'checkpoint'), scenario([LABELS[%w[think plan code].index(phase)]], queue: queue))
      assert_equal [['workflow', 'run', 'think.yml', '-f', 'issue_number=7']], dispatches
    end
    entry = steps('prove').find { |item| item['name'] == 'Trigger next labeled issue in FIFO queue' }
    run_step(entry, scenario([], queue: queue))
    assert_equal [['workflow', 'run', 'think.yml', '-f', 'issue_number=7']], dispatches
  end

  def test_failures_remove_trigger_labels_and_advance_queue
    PHASES.each do |phase|
      entry = steps(phase).find { |item| item['name'].to_s.match?(/(?:if #{phase.capitalize} fail|if #{phase.capitalize} failed)/) }
      refute_nil entry, phase
      run_step(entry, scenario([], queue: [queue_issue(7, ['1-think'])]))
      edit = @calls.find { |args| args.first(2) == %w[issue edit] }
      assert_equal 'needs:developer', edit[edit.index('--add-label') + 1]
      assert_equal LABELS, edit[edit.index('--remove-label') + 1].split(',')
      assert_equal phase == 'prove' ? [] : [['workflow', 'run', 'think.yml', '-f', 'issue_number=7']], dispatches
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
      assert_includes entry.fetch('if'), phase == 'think' ? "steps.fifo.outputs.resumed_stage == 'none'" : "steps.resolve.outputs.skip != 'true'"
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
        labels = job.fetch('if').scan(/github.event.label.name == '([^']+)'/).flatten
        assert_equal LABELS, labels, repository
        expected = "github.event_name == 'workflow_dispatch' || " \
                   "(github.event_name == 'issues' && github.event.issue.state == 'open' && " \
                   "github.event.label.name != '' && (" \
                   "#{LABELS.map { |label| "github.event.label.name == '#{label}'" }.join(' || ')}))"
        assert_equal expected, job.fetch('if').split.join(' '), repository
        assert_equal title, job.fetch('with').fetch('project_title')
        assert_equal '1pizzateam/coding-pal/.github/workflows/pipeline-think.yml@main', job.fetch('uses')
        plan = YAML.load_file(File.join(directory, 'plan.yml'))
        plan_triggers = plan['on'] || plan.fetch(true)
        assert_equal [wrapper.fetch('name')], plan_triggers.fetch('workflow_run').fetch('workflows')
        %w[plan code prove].each do |phase|
          current = YAML.load_file(File.join(directory, "#{phase}.yml"))
          upstream_phase = { 'plan' => 'think', 'code' => 'plan', 'prove' => 'code' }.fetch(phase)
          upstream = YAML.load_file(File.join(directory, "#{upstream_phase}.yml"))
          events = current['on'] || current.fetch(true)
          assert_equal [upstream.fetch('name')], events.fetch('workflow_run').fetch('workflows')
          assert_equal "Pipeline - #{phase.capitalize}", current.fetch('name')
        end
        audits = YAML.load_file(File.join(directory, 'audits.yml'))
        assert_equal 'Audit - Run audit', audits.fetch('name')
      end
    end
  end
end
