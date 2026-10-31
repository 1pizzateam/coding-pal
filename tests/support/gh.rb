require 'json'
require 'open3'

scenario = JSON.parse(File.read(ENV.fetch('TEST_SCENARIO')))
File.open(ENV.fetch('TEST_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }

def reject_command(message)
  File.open(ENV.fetch('TEST_VIOLATIONS'), 'a') { |file| file.puts(message) }
  warn message
  exit 1
end

def argument(name)
  index = ARGV.index(name)
  index && ARGV[index + 1]
end

result = case ARGV.first(2)
         when ['issue', 'view']
           scenario.fetch('issue')
         when ['pr', 'list']
           scenario.fetch('prs', [])
         when ['run', 'list']
           scenario.fetch('runs', [])
         when ['api', 'graphql']
           if scenario['api_failure']
             warn 'Mock GitHub API permission denied'
             exit 1
           end
           query = ARGV.find { |value| value.start_with?('query=', 'mutation=') }
           reject_command('Missing GraphQL query') unless query
           case query
           when /updateProjectV2ItemFieldValue/
             { 'data' => { 'updateProjectV2ItemFieldValue' => { 'projectV2Item' => { 'id' => 'ITEM' } } } }
           when /addProjectV2ItemById/
             { 'data' => { 'addProjectV2ItemById' => { 'item' => { 'id' => 'ITEM' } } } }
           when /projectsV2/
             scenario.fetch('project')
           when /issues\(states: \[OPEN\]/
             { 'data' => { 'repository' => { 'issues' => { 'nodes' => scenario.fetch('queue', []) } } } }
           else
             reject_command("Unexpected GraphQL operation: #{query}")
           end
         when ['workflow', 'run']
           reject_command("Unexpected dispatch: #{ARGV.inspect}") unless %w[think.yml code.yml prove.yml].include?(ARGV[2])
           nil
         when ['label', 'create'], ['issue', 'edit'], ['issue', 'comment'], ['pr', 'edit']
           nil
         else
           reject_command("Unexpected gh command: #{ARGV.inspect}")
         end

if result
  json = JSON.generate(result)
  filter = argument('--jq')
  if filter
    output, error, status = Open3.capture3('jq', '-r', filter, stdin_data: json)
    reject_command("Invalid --jq filter: #{error}") unless status.success?
    print output
  else
    puts json
  end
end
