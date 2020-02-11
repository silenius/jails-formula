# jails-formula

SaltStack FreeBSD jails formula to remotely provision and configure FreeBSD thick jails.

## Prerequisites

A Saltstack Minion must be installed and configured on the **host**.

This formula depends on https://github.com/silenius/zfs-formula if ZFS is used.

## Usage

Clone the repository on the Saltstack Master and add the path in the `file_roots` section of the Master configuration file.

See https://github.com/silenius/jails-formula/blob/master/pillar.example for an example configuration. 

Per -RELEASE defaults are provided in https://github.com/silenius/jails-formula/tree/master/jails/defaults
