Vagrant.configure("2") do |config|
  
  # Number of nodes to provision
  numNodes = 4

  # IP Address Base for private network
  ipAddrPrefix = "192.168.56.10"

  # Define Number of RAM for each node
  config.vm.provider "virtualbox" do |v|
    v.memory = 1024 # v.customize ["modifyvm", :id, "--memory", 1024] # default is 512
    v.cpus = 1 # v.customize ["modifyvm", :id, "--cpus", 1] # default is 1
    v.customize ["modifyvm", :id, "--ioapic", "on"]  # Makes provisioning MUCH faster when using multiple cpus ... http://serverfault.com/questions/74672/why-should-i-enable-io-apic-in-virtualbox
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"] # incase I use Ubutu12 see ... http://askubuntu.com/questions/238040/how-do-i-fix-name-service-for-vagrant-client
  end

  # Provision Config for each of the nodes
  1.upto(numNodes) do |num|
    nodeName = ("node" + num.to_s).to_sym
    config.vm.define nodeName do |node|
      node.vm.box = "puppetlabs/centos-6.6-64-puppet"
      node.vm.network :private_network, ip: ipAddrPrefix + num.to_s
      puts "Private network (host only) ip : http://#{ipAddrPrefix + num.to_s}:8091"
      node.vm.provider "virtualbox" do |v|
        v.name = "Couchbase Server Node " + num.to_s
      end
    end
  end
end