#
# Cookbook Name:: storm
# Recipe:: default
#
# Copyright 2012, Webtrends, Inc.
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

include_recipe "java"
include_recipe "runit"


install_dir = "#{node['storm']['root_dir']}/storm-#{node['storm']['version']}"

node.set['storm']['lib_dir'] = "#{install_dir}/lib"
node.set['storm']['conf_dir'] = "#{install_dir}/conf"
node.set['storm']['bin_dir'] = "#{install_dir}/bin"
node.set['storm']['install_dir'] = install_dir

# install dependency packages
%w{unzip python}.each do |pkg|
  package pkg do
    action :install
  end
end



# need to control the versions of zeromq and jzmq, see:
# https://github.com/nathanmarz/storm/wiki/Installing-native-dependencies
case node[:platform]
when "redhat"

    cookbook_file "/tmp/zeromq-2.1.7-1.el6.x86_64.rpm" do
      source "zeromq-2.1.7-1.el6.x86_64.rpm"
    end

    cookbook_file "/tmp/jzmq-2.1.0-1.el6.x86_64.rpm" do
      source "jzmq-2.1.0-1.el6.x86_64.rpm"
    end

    package "zeromq" do
      action :install
      source "/tmp/zeromq-2.1.7-1.el6.x86_64.rpm"
    end
      
    package "jzmq" do
      action :install
      source "/tmp/jzmq-2.1.0-1.el6.x86_64.rpm"
    end

when "ubuntu"
  # TODO need to fix this to follow what I did for redhat
  package "zeromq" do
    action :install
    source "debs/zeromq_2.1.7-1_amd64.deb"
  end
  package "jzmq" do
    action :install
    source "debs/jzmq_2.1.0-1_amd64.deb"
  end
end

package "zeromq" do
  action :install
  version "2.1.7-1.el6"
end

package "jzmq" do
  action :install
  version "2.1.0-1.el6"
end

#locate the nimbus for this storm cluster
if node.recipes.include?("storm::nimbus")
  nimbus_host = node
else
  nimbus_host = search(:node, "role:storm_nimbus AND role:#{node['storm']['cluster_role']} AND chef_environment:#{node.chef_environment}").first
end

# search for zookeeper servers
zookeeper_quorum = Array.new
search(:node, "role:zookeeper AND chef_environment:#{node.chef_environment}").each do |n|
	zookeeper_quorum << n[:fqdn]
end

# setup storm group
group "storm"

# setup storm user
user "storm" do
  comment "Storm user"
  gid "storm"
  shell "/bin/bash"
  home "/home/storm"
  supports :manage_home => true
end

# storm looks for storm.yaml in ~/.storm/storm.yaml so make a link
link "/home/storm/.storm" do
  to node['storm']['conf_dir']
end 

# setup directories
%w{conf_dir local_dir log_dir install_dir bin_dir}.each do |name|
  directory node['storm'][name] do
    owner "storm"
    group "storm"
    action :create
    recursive true
  end
end

# download storm
remote_file "#{Chef::Config[:file_cache_path]}/storm-#{node[:storm][:version]}.tar.gz" do
  source "#{node['storm']['download_url']}/storm-#{node['storm']['version']}.tar.gz"
  owner  "storm"
  group  "storm"
  mode   00744
  action :create_if_missing
end

# uncompress the application tarball into the install directory
execute "tar" do
  user    "storm"
  group   "storm"
  creates node['storm']['lib_dir']
  cwd     node['storm']['root_dir']
  command "tar zxvf #{Chef::Config[:file_cache_path]}/storm-#{node['storm']['version']}.tar.gz"
end

# create a link from the specific version to a generic current folder
link "#{node['storm']['root_dir']}/current" do
	to node['storm']['install_dir']
end

# storm.yaml
template "#{node['storm']['conf_dir']}/storm.yaml" do
  source "storm.yaml.erb"
  mode 00644
  variables(
    :nimbus => nimbus_host,
    :zookeeper_quorum => zookeeper_quorum
  )
end

# sets up storm users profile
template "/home/storm/.profile" do
  owner  "storm"
  group  "storm"
  source "profile.erb"
  mode   00644
  variables(
    :storm_dir => node['storm']['install_dir']
  )
end

template "#{node['storm']['install_dir']}/bin/killstorm" do
  source  "killstorm.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :log_dir => node['storm']['log_dir']
  })
end
