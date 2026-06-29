#!/bin/env bash
pactl set-card-profile alsa_card.pci-0000_c4_00.5-platform-amd_sdw off
sleep 1
pactl set-card-profile alsa_card.pci-0000_c4_00.5-platform-amd_sdw pro-audio
