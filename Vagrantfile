# Vagrantfile - Place this at the project root

Vagrant.configure("2") do |config|
  # Use a recent Fedora box suitable for running Bash scripts
  config.vm.box = "generic/fedora39"

  # The communicator for Linux is SSH (this is the default)
  config.vm.communicator = "ssh"

  # Vagrant automatically syncs the project root to /vagrant inside the VM.
  # This line is not strictly necessary as it's the default, but it makes it explicit.
  config.vm.synced_folder ".", "/vagrant", type: "virtiofs"

  # This is the CI part. This command runs automatically after `vagrant up`.
  # It changes to the project directory and executes your test runner.
  config.vm.provision "shell", inline: <<-SHELL
    set -euxo pipefail

    echo "--- Navigating to project directory ---"
    cd /vagrant

    echo "--- Installing dependencies (if any) ---"
    # Add commands to install dependencies like bats, jq, etc.
    # sudo dnf install -y bats jq

    echo "--- Running all tests ---"
    # Execute your test runner script, mirroring your `justfile` command.
    ./run_tests.bash -r test
  SHELL

  # Optional: Configure the libvirt provider settings
  config.vm.provider "libvirt" do |v|
    v.memory = 2048
    v.cpus = 2
  end
end
