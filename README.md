# Ansible Collection - blockchain.tools

These are common roles that we use while setting up devnets. All of
the configuration here should be generic across different types of
nodes (zkEVM, PoS, Edge, Avail, etc).

Right now all of the tasks assume that they're running on Debian /
Ubuntu.

This is how you would install the collection for use currently.

```bash
ansible-galaxy collection install git+https://github.com/praetoriansentry/blockchain.tools.git,main
```

In order to use the role from a collection we might do something like this:

```yml
- name: Basic setup and packages
  hosts: all
  collections:
    - blockchain.tools
  roles:
    - init
    - atop # this is imported from the collection
  tags:
    - init
```
