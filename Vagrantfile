# -*- mode: ruby -*-
# vi: set ft=ruby :
home = ENV['HOME']
Vagrant.configure("2") do |config|
  # https://docs.vagrantup.com.

  config.vm.box = "centos/8"  # Для экспериментов возьмем образ CentOS 8

   config.vbguest.no_install = true # отменим установку VBoxGuestAdditions
   config.vm.provider "virtualbox" do |vb|
    second_disk = home + "/VirtualBox VMs/disks/second_disk.vmdi" # расположение второго диска
    needsController = false
    unless File.exist?(second_disk) # если файла не существует, создадим его и ниже создадим и подключим контроллер SATA
	  vb.customize ['createhd', '--filename', second_disk, '--variant', 'Fixed', '--size', 10000]
        needsController =  true
    end
    if needsController == true
        vb.customize ["storagectl", :id, "--name", "SATA", "--add", "sata" ]
        vb.customize ['storageattach', :id,  '--storagectl', 'SATA', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', second_disk]
    end
    vb.memory = "1024"
    vb.cpus = "2"
    vb.gui = true
   end

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
   config.vm.provision "file", source: "stage-2.sh", destination: "stage-2.sh"
   config.vm.provision "shell", inline: <<-SHELL
     echo "*** Устанавливаем mdadm, at и обновляем grub2 ***"
     yum install -y mdadm at grub2-pc grub2-tools > /dev/null 2>&1
     # Запускаем демон планировщика, понадобится для второй стадии переноса
     systemctl start atd
     systemctl enable atd
     echo "*** Отключаем SELINUX ***"
     setenforce 0
     echo SELINUX=disabled > /etc/selinux/config
     echo "*** Копируем таблицу разделов на второй HDD ***"
     sfdisk -d /dev/sda | sfdisk /dev/sdb > /dev/null 2>&1
   SHELL

$script = <<-'SCRIPT'
fdisk /dev/sdb << DONE
  t
  fd
  w
DONE
  SCRIPT

  config.vm.provision "shell", inline: $script

  config.vm.provision "shell", inline: <<-SHELL

     echo "*** Обновим таблицу разделов ***"
     partprobe
     echo "*** Очистим суперблоки на втором HDD ***"
     mdadm --zero-superblock /dev/sdb1 > /dev/null 2>&1
     echo "*** Создаем RAID1 с одним диском ***"
     echo y|mdadm --create /dev/md0 --level=1 --raid-devices=2 missing /dev/sdb1 > /dev/null 2>&1
     echo "*** Форматируем и монтируем полученный RAID-недомассив ***"
     mkfs.xfs /dev/md0 > /dev/null 2>&1
     mount /dev/md0 /mnt/
     echo "*** Копируем текущую систему на RAID-массив ***"
     rsync -axu / /mnt/
     echo "*** Монтируем оставшиеся каталоги ***"
     mount --bind /proc /mnt/proc && mount --bind /dev /mnt/dev && mount --bind /sys /mnt/sys && mount --bind /run /mnt/run
     echo "*** Заменяем точку монтирования в /etc/fstab ***"
     chroot /mnt sh -c "echo -e 'UUID=`blkid -s UUID -o value /dev/md0` /  xfs  defaults  0 0\n/swapfile none swap defaults 0 0' > /etc/fstab"
     echo "*** Создаем конфигурационный файл /etc/mdadm ***"
     chroot /mnt sh -c "mdadm --detail --scan > /etc/mdadm.conf"
     echo "*** Создаем новый initramfs ***"
     chroot /mnt mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.old
     chroot /mnt dracut /boot/initramfs-$(uname -r).img $(uname -r)
     echo "*** Добавляем опцию rd.auto=1 в настройки grub2 ***"
     chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"rd.auto=1 /' /etc/default/grub
     echo "*** Перенастроим grub2 и установим его на второй HDD ***"
     chroot /mnt sh -c "grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1"
     chroot /mnt sh -c "grub2-install /dev/sdb > /dev/null 2>&1"
     echo "!!!====================================================================!!!"
     echo "!!!                                                                    !!!"
     echo "!!!           Система будет перезагружена через одну минуту            !!!"
     echo "!!! Вернитесь в окно VirtualBox'а и при начальной загрузке нажмите F12 !!!"
     echo "!!!                  В boot device выберите второй диск                !!!"
     echo "!!!                                                                    !!!"
     echo "!!!  Через пять минут выполнится скрипт, завершающий перенос системы   !!!"
     echo "!!! Для проверки статуса RAID-массива выполните watch cat /proc/mdstat !!!"
     echo "!!!                                                                    !!!"
     echo "!!!====================================================================!!!"

     at -f /home/vagrant/stage-2.sh now + 5 minutes > /dev/null 2>&1
     shutdown -r > /dev/null 2>&1
   SHELL
end
