#!/bin/bash
sudo fdisk /dev/sda << DONE
t
fd
w
DONE

sudo mdadm --manage /dev/md0 --add /dev/sda1
sudo grub2-install /dev/sda

echo "Система перенесена"
echo "Проверить статус синхронизации можно командой cat /proc/mdstat"
echo "После завершения синхронизации дисков можно загружать систему с /dev/sda"

