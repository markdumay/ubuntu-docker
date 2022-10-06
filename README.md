# ubuntu-docker

<!-- Tagline -->
<p align="center">
    <b>Install Docker on a Mint Ubuntu 20.04 LTS Server</b>
    <br />
</p>


## Revised steps (prod)
1. Install Ubuntu 20.04 from image (VPS Control Panel)
2. Add users (ansible, admin)
3. Create partitions
4. Run hardening script
5. Configure ufw
6. Install Docker

## Revised steps (test)
1. Install vagrant `https://www.vagrantup.com/downloads`
2. Install vagrant plugin `vagrant plugin install vagrant-vbguest`
3. Install virtualbox `https://www.virtualbox.org/wiki/Downloads`
4. Boot image `vagrant up`
5. Add vagrant host `echo test ansible_port=22 ansible_host=10.7.8.45 >> /etc/ansible/hosts`
6. Install ansible `https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html`
7. Install hardening ansible role `ansible-galaxy role install konstruktoid.hardening`
8. Harden image ``

Run playbook


<!-- Badges -->
<p align="center">
    <a href="https://github.com/markdumay/ubuntu-docker/commits/master" alt="Last commit">
        <img src="https://img.shields.io/github/last-commit/markdumay/ubuntu-docker.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-docker/issues" alt="Issues">
        <img src="https://img.shields.io/github/issues/markdumay/ubuntu-docker.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-docker/pulls" alt="Pulls">
        <img src="https://img.shields.io/github/issues-pr-raw/markdumay/ubuntu-docker.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-docker/blob/master/LICENSE" alt="License">
        <img src="https://img.shields.io/github/license/markdumay/ubuntu-docker.svg" />
    </a>
</p>

<!-- Table of Contents -->
<p align="center">
  <a href="#about">About</a> •
  <a href="#prerequisites">Prerequisites</a> •
  <a href="#deployment">Deployment</a> •
  <a href="#usage">Usage</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#credits">Credits</a> •
  <a href="#donate">Donate</a> •
  <a href="#license">License</a>
</p>


## About
[Docker][docker_info] is a lightweight virtualization application that gives you the ability to run containers directly on your server. *Ubuntu-docker* is a basic shell script to harden a [Ubuntu][ubuntu_url] 20.04 LTS host and to install Docker and Docker Compose on this host. The host is setup as a Docker Swarm manager.

<!-- TODO: add tutorial deep-link 
Detailed background information is available on the author's [personal blog][blog].
-->

## Prerequisites
*Ubuntu-docker* runs on a remote server with Ubuntu 20.04 LTS installed. Other prerequisites are:

* **SSH admin access is required** - Ubuntu-docker runs as a shell script on the terminal.
* **A Ubuntu One account is recommended** - Canonical offers a *livepatch* service, which is free for personal use up to 3 machines. You can register at [this][livepatch] site. Once registered you get a token linked to your account.

## Deployment
Deployment of *ubuntu-docker* is a matter of cloning the GitHub repository. Login to your server via SSH first. Assuming you are in the working folder of your choice, clone the repository files. Git automatically creates a new folder `ubuntu-docker` and copies the files to this directory. Then change your current folder to simplify the execution of the shell script.

```console
git clone https://github.com/markdumay/ubuntu-docker.git
cd ubuntu-docker
```

<!-- TODO: TEST CHMOD -->

## Usage
*Ubuntu-docker* requires `sudo` rights. Use the following command to invoke `ubuntu-docker.sh` from the command line.

```
sudo ./ubuntu-docker.sh [OPTIONS] COMMAND
```

If a `.env` file is present, *ubuntu-docker* reads the following variables.


| Variable              | Default   | Description |
|-----------------------|-----------|-------------|
| IP_SSH_ALLOW_HOSTNAME |           | Restricts SSH access to the IP address associated with the domain (e.g. `ddns.example.com`) if specified. The domain is polled every 5 minutes to cater for changes (such as dynamic IP addresses). |
| IP_SSH_PORT           | 22        | The SSH port to be configured by the firewall (UWF), defaults to `22`. |
| IPV6                  | false     | Indicates whether IPv6 support is required, disabled by default. |
| CANONICAL_TOKEN       |           | Unique token associated with your Ubuntu One account, used for live patching. |

### Commands
*Ubuntu-docker* supports the following commands. 

| Command       | Argument  | Description |
|---------------|-----------|-------------|
| **`init`**    |           | Hardens a mint Ubuntu 20.04 LTS server |
| **`install`** |           | Installs Docker, Docker Compose, and Docker Swarm on a Ubuntu 20.04 LTS host |

The `init` command executes the following sequence of steps.
1. **Create a Non-Root User with Sudo Privileges** - Creates a non-root user `admin` with administrative privileges.
2. **Disable Remote Root Login** - Ensures `root` can no longer login remotely to the server. Instead, the `admin` user with explicitly elevated privileges through `sudo` is used for server administration.
3. **Secure Shared Memory** - Mounts `/run/shm` in read-only mode, preventing the ability of data being passed between applications.
4. **Make Boot Files Read-Only** - Prevents unauthorized modifications to the server boot files.
5. **Install Fail2Ban** - Prevents brute-force attacks by banning repeat login attempts from a single IP address.
6. **Enable Livepatch** - If `CANONICAL_TOKEN` is specified in `.env`, automatically applies critical kernel security fixes without rebooting.
7. **Enable Swap Limit Support** - Updates grub to enable swap limit support (recommended by Docker, requires reboot).
8. **Enable Firewall** - Installs Uncomplicated Firewall (UFW) to only allow web traffic (port 80 and port 443) and SSH-traffic (port `IP_SSH_PORT`) to the server. If `IP_SSH_ALLOW_HOSTNAME` is specified in the `.env` file, a cron job is executed every 5 minutes to poll for the IP address associated with the hostname. SSH access is then restricted to this IP address only.

The `install` command executes the following workflow.
1. **Install Docker** - Installs the latest Docker Engine from the official Docker repository.
2. **Add Admin** - Adds the `admin` user to the `docker` user group.
3. **Configure Docker Daemon** - Implements several Docker security audit recommendations.
4. **Enable Docker Audit** - Enables auditing of Docker.
5. **Docker Environment** - Ensures Content Trust for Docker is enabled (verifies signatures of Docker images).
6. **Download and Install Docker Compose** - Downloads and installs the latest Docker Compose binary.
7. **Initialize Docker Swarm** - Initializes Docker to become a Swarm Manager.
8. **Encrypt Ingress Network** - Encrypts default overlay network for Docker Swarm.
9. **Configure Ports for Swarm Communication** - Enables specific TCP and UDP ports needed for Docker Swarm communication between nodes if the option `--ports` is present, disables ports otherwise. 



<!-- TODO: SSH keys -->


### Options
*Ubuntu-docker* supports the following options. 

| Option      | Alias       | Argument   | Description |
|-------------|-------------|------------|-------------|
| `-f`        | `--force`   |            | Force the installation and bypass compatibility checks |
| `-p`        | `--ports`   |            | Open Docker Swarm ports (disabled by default) |


## Contributing
1. Clone the repository and create a new branch 
    ```
    $ git checkout https://github.com/markdumay/Ubuntu-docker.git -b name_for_new_branch
    ```
2. Make and test the changes
3. Submit a Pull Request with a comprehensive description of the changes

## Credits
*Ubuntu-docker* is inspired by the following blog articles:
* Brian Boucheron - [How To Audit Docker Host Security with Docker Bench for Security on Ubuntu 16.04][digital_ocean_bench]
* Brian Hogan - [How To Install and Use Docker on Ubuntu 20.04][digital_ocean_setup]
* Vladimir Rakov - [How to Harden your Ubuntu 18.04 Server][hostadvice]
* Thomas @ euroVPS - [20 Ways to Secure Your Linux VPS so You Don’t Get Hacked][eurovps]
* Michael Aboagye - [How to Secure Docker for Production Environment?][geekflare]

## Donate
<a href="https://www.buymeacoffee.com/markdumay" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/lato-orange.png" alt="Buy Me A Coffee" style="height: 51px !important;width: 217px !important;"></a>

## License
<a href="https://github.com/markdumay/ubuntu-docker/blob/master/LICENSE" alt="License">
    <img src="https://img.shields.io/github/license/markdumay/ubuntu-docker.svg" />
</a>

Copyright © [Mark Dumay][blog]



<!-- MARKDOWN PUBLIC LINKS -->
[docker_info]: https://www.docker.com/why-docker
[ubuntu_url]: https://ubuntu.com
[digital_ocean_bench]: https://www.digitalocean.com/community/tutorials/how-to-audit-docker-host-security-with-docker-bench-for-security-on-ubuntu-16-04
[digital_ocean_setup]: https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-20-04
[livepatch]: https://ubuntu.com/livepatch
[eurovps]: https://www.eurovps.com/blog/20-ways-to-secure-linux-vps/
[hostadvice]: https://hostadvice.com/how-to/how-to-harden-your-ubuntu-18-04-server/
[geekflare]: https://geekflare.com/securing-docker-for-production/

<!-- MARKDOWN MAINTAINED LINKS -->
<!-- TODO: add blog link
[blog]: https://markdumay.com
-->
[blog]: https://github.com/markdumay
[repository]: https://github.com/markdumay/ubuntu-docker.git