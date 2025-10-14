# Vagrantfile - Place this at the project root

Vagrant.configure("2") do |config|

  # --- Fedora (Linux) Test Machine ---
  config.vm.define "fedora" do |fedora|
    fedora.vm.box = "generic/fedora39"

    # Use the virtiofs fix for fast, native file sharing
    fedora.vm.synced_folder ".", "/vagrant", type: "9p"

    # Provision with your existing bash script
    fedora.vm.provision "shell", path: "run_tests.bash"

    fedora.vm.provider "libvirt" do |v|
      v.driver = "qemu"
      v.memory = 2048
      v.cpus = 2
    end
  end


  # --- Windows Test Machine ---
  config.vm.define "windows" do |windows|
    # Find a suitable Windows box for libvirt on Vagrant Cloud
    windows.vm.box = "generic/windows10"

    # IMPORTANT: Windows uses WinRM, not SSH
    windows.vm.communicator = "winrm"

    # You would create a PowerShell script to run your tests on Windows
    windows.vm.provision "shell", path: "run_tests_windows.ps1"

    windows.vm.provider "libvirt" do |v|
      # Windows needs more RAM
      v.memory = 4096
      v.cpus = 2
    end
  end

end
