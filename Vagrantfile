# -*- mode: ruby -*-
# vim: ft=ruby:

Vagrant.configure(2) do |config|
  config.vm.box = "bento/debian-9.2"
  config.vm.provision(
    "file",
    source: "unbootstrap.bash",
    destination: "unbootstrap.bash"
  )
  config.vm.provision(
    "shell",
    inline: "sudo install -m 0744 unbootstrap.bash /usr/local/sbin/unbootstrap"
  )
end
