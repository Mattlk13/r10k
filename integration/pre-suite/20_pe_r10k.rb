require 'git_utils'
require 'r10k_utils'
require 'master_manipulator'
test_name 'CODEMGMT-21 - C59119 - Configure r10k for Puppet Enterprise'

#Init
env_path = on(master, puppet('config print environmentpath')).stdout.rstrip
prod_env_path = File.join(env_path, 'production')

r10k_config_path = get_r10k_config_file_path(master)

git_repo_path = '/git_repos'
git_repo_name = 'environments'
git_control_remote = File.join(git_repo_path, "#{git_repo_name}.git")
git_provider = ENV['GIT_PROVIDER'] || 'shellgit'
r10k_fqp = get_r10k_fqp(master)

step 'Get PE Version'
pe_version = get_puppet_version(master)
fail_test('This pre-suite requires PE 3.7 or above!') if pe_version < 3.7

#In-line files
r10k_conf = <<-CONF
cachedir: '/var/cache/r10k'
git:
  provider: '#{git_provider}'
sources:
  control:
    basedir: "#{env_path}"
    remote: "#{git_control_remote}"
CONF

#Setup
step 'Remove Current Puppet "production" Environment'
on(master, "rm -rf #{prod_env_path}")

step 'Configure r10k'
create_remote_file(master, r10k_config_path, r10k_conf)
on(master, "chmod 644 #{r10k_config_path}")

step 'Deploy "production" Environment via r10k'
on(master, "#{r10k_fqp} deploy environment -v")

step 'Disable Environment Caching on Master'
on(master, puppet('config set environment_timeout 0 --section main'))

#This should be temporary until we get a better solution.
step 'Disable Node Classifier'
on(master, puppet('config', 'set node_terminus plain', '--section master'))

step 'Restart the Puppet Server Service'
restart_puppet_server(master)

step 'Run Puppet Agent on All Nodes'
run_puppet_agent(agents, 'production')

# The production run above re-applies the PE agent profile, which enables and
# starts Service[puppet]. Its daemonized periodic runs would otherwise hold
# agent_catalog_run.lock during r10k deploys, config writes, and teardown, and
# race the explicit "puppet agent --test" runs in the tests. Stop and disable
# the service once here to cover those windows; the tests run through
# run_puppet_agent, which adds --waitforlock 1 to handle the case where a run
# against "production" re-enables the service (see integration/lib/r10k_utils.rb).
step 'Stop and disable the puppet agent service to avoid catalog-run lock races'
on(hosts, puppet('resource', 'service', 'puppet', 'ensure=stopped', 'enable=false'))
