Все действия постарался максимально автоматизировать. Неавтоматизирован только выбор диска для загрузки.

- Для эксперимента выбран образ centos/8.
- Для работы необходим графический интерфейс (vb.gui = true).
- Для запуска второй стадии процесса переноса используется планировщик at и файл скрипта

-----

Для начала создадим второй диск, для этого в Vagrantfile добавляем:

    second_disk = home + "/VirtualBox VMs/disks/second_disk.vmdi" # расположение файла диска
    needsController = false
    unless File.exist?(second_disk) # если файла не существует, создадим его и ниже создадим и подключим контроллер SATA
      vb.customize ['createhd', '--filename', second_disk, '--variant', 'Fixed', '--size', 10000]
      needsController =  true
    end
    if needsController == true
      vb.customize ["storagectl", :id, "--name", "SATA", "--add", "sata" ]
      vb.customize ['storageattach', :id,  '--storagectl', 'SATA', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', second_disk]
    end

Остальные действия проходят в provision VirtualBox'а (config.vm.provision "shell", inline: <<-SHELL)
-----
##### Устанавливаем mdadm, at и обновляем grub2
    yum install -y mdadm at grub2-pc grub2-tools
##### Запускаем демона планировщика, понадобится для второй стадии процесса переноса
    systemctl start atd
    systemctl enable atd

##### Отключаем SELINUX
    setenforce 0
    echo SELINUX=disabled > /etc/selinux/config
##### Копируем таблицу разделов с sda на sdb
    sfdisk -d /dev/sda | sfdisk /dev/sdb
-----
Далее используется inline script
-----
##### Меняем тип раздела на Linux raid autodetect
    $script = <<-'SCRIPT'
    fdisk /dev/sdb << DONE
      t
      fd
      w
    DONE
    SCRIPT
    config.vm.provision "shell", inline: $script

-----
Вернулись в inline SHELL
-----
##### На всякий случай обновляем таблицу разделов
    partprobe
##### и очищаем суперблоки от старых рэйдов
    mdadm --zero-superblock /dev/sdb1

##### Создаем RAID 1 с одним диском
    echo y|mdadm --create /dev/md0 --level=1 --raid-devices=2 missing /dev/sdb1

##### Форматируем и монтируем массив
    mkfs.xfs /dev/md0
    mount /dev/md0 /mnt/

##### Копируем текущую систему на RAID-массив
    rsync -axu / /mnt/

##### Монтируем системные каталоги
    mount --bind /proc /mnt/proc && mount --bind /dev /mnt/dev && mount --bind /sys /mnt/sys && mount --bind /run /mnt/run

#### Далее используем chroot /mnt
##### заменяем точку монтирования в /etc/fstab
    chroot /mnt sh -c "echo -e 'UUID=`blkid -s UUID -o value /dev/md0` /  xfs  defaults  0 0\n/swapfile none swap defaults 0 0' > /etc/fstab"
##### создаем конфиг mdadm.conf
    chroot /mnt sh -c "mdadm --detail --scan > /etc/mdadm.conf"
##### создаем новый initramfs
     chroot /mnt mv /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.old
     chroot /mnt dracut /boot/initramfs-$(uname -r).img $(uname -r)
##### добавим rd.auto в настройки grub
    chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"rd.auto=1 /' /etc/default/grub
##### перенастроим grub и установим его на новый диск
     chroot /mnt sh -c "grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1"
     chroot /mnt sh -c "grub2-install /dev/sdb > /dev/null 2>&1"
##### запланируем запуск скрипта для окончания процесса переноса
     at -f /home/vagrant/stage-2.sh now + 2 minutes > /dev/null 2>&1
##### перезагружаем систему
    shutdown -r

При перезагрузке необходимо выбрать загрузку со второго диска (F12 в VirtualBox)
-----
Далее отработает скрипт stage-2.sh, который и завершит перенос системы

-----
##### stage-2.sh
    sudo fdisk /dev/sda << DONE
    t
    fd
    w
    DONE
    sudo mdadm --manage /dev/md0 --add /dev/sda1
    sudo grub2-install /dev/sda
-----
Проверить статус синхронизации можно командой

    cat /proc/mdstat
После синхронизации система готова к работе.
