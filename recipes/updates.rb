#
# Cookbook Name:: coldfusion11
# Recipe:: updates
#
# Copyright 2012, NATHAN MISCHE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Chef::Recipe
  include CF11Entmanager
end

if Chef::Version.new(Chef::VERSION).major >= 11
	has_java = run_context.loaded_recipe?("java")
else
	has_java = node.recipe?("java")
end

if has_java && node['java']['install_flavor'] == "oracle"
  node.set['cf11']['java']['home'] = node['java']['java_home']
end
unless node['cf11']['java']['home']
  node.set['cf11']['java']['home'] = node['cf11']['installer']['install_folder']
end

update_dirs = node['cf11']['updates']['dirs'].dup

# Make sure we have the latest node data
ruby_block "refresh_node_data_for_updates" do
  block do
    update_node_instances(node)
  end
end

# Create the CF 10 update properties file
template "#{Chef::Config['file_cache_path']}/update-installer.properties" do
  source "update-installer.properties.erb"
  mode "0644"
  owner node['cf11']['installer']['runtimeuser']
end

# Run updates
node['cf11']['updates']['urls'].each do | update |

  # Only apply an update if it or a later update doesn't exist
  if update_dirs.select { |x| Dir.exists?("#{node['cf11']['installer']['install_folder']}/cfusion/hf-updates/#{x}") }.empty?

    file_name = update.split('/').last
    sodo_name = "cf11_#{file_name.split('.').first}_sudo"

    sudo sodo_name do
      user node['cf11']['installer']['runtimeuser']
      nopasswd true
      action :install
    end

    # Download the update
    remote_file "#{Chef::Config['file_cache_path']}/#{file_name}" do
      source update
      action :create_if_missing
      mode "0744"
      owner node['cf11']['installer']['runtimeuser']
    end

    # Run the installer
    execute "run_cf11_#{file_name.split('.').first}_installer" do
      command "#{node['cf11']['java']['home']}/jre/bin/java -jar #{file_name} -i silent -f update-installer.properties"
      action :run
      user node['cf11']['installer']['runtimeuser']
      cwd Chef::Config['file_cache_path']
    end

    # Some updates require you to re-run wsconfig, so just do it if wsconfig is configured and an update was applied
    execute "start_cf_for_coldfusion11_updater_wsconfig" do
      command "/bin/true"
      notifies :start, "service[coldfusion]", :delayed
      notifies :run, "execute[uninstall_wsconfig]", :delayed
      notifies :run, "execute[install_wsconfig]", :delayed
      only_if "#{node['cf11']['installer']['install_folder']}/cfusion/runtime/bin/wsconfig -list | grep 'Apache : #{node['apache']['dir']}'"
    end

    sudo sodo_name do
      user node['cf11']['installer']['runtimeuser']
      nopasswd true
      action :remove
    end

  end

  update_dirs.shift

end
