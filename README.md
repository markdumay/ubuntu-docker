# ubuntu-secure

<!-- Tagline -->
<p align="center">
    <b>Harden a mint Ubuntu 20.04 LTS server</b>
    <br />
</p>


<!-- Badges -->
<p align="center">
    <a href="https://github.com/markdumay/ubuntu-secure/commits/master" alt="Last commit">
        <img src="https://img.shields.io/github/last-commit/markdumay/ubuntu-secure.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-secure/issues" alt="Issues">
        <img src="https://img.shields.io/github/issues/markdumay/ubuntu-secure.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-secure/pulls" alt="Pulls">
        <img src="https://img.shields.io/github/issues-pr-raw/markdumay/ubuntu-secure.svg" />
    </a>
    <a href="https://github.com/markdumay/ubuntu-secure/blob/master/LICENSE" alt="License">
        <img src="https://img.shields.io/github/license/markdumay/ubuntu-secure.svg" />
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
[Ubuntu][ubuntu_url] is an open source software operating system that runs from the desktop to the cloud. It is a popular choice for cloud providers and has good support for container operations. *Ubuntu-secure* is a basic shell script to harden a mint Ubuntu server installation. The currently supported version is 20.04 LTS.

<!-- TODO: add tutorial deep-link 
Detailed background information is available on the author's [personal blog][blog].
-->

## Prerequisites
*Ubuntu-secure* runs on a remote server with Ubuntu 20.04 LTS installed. Other prerequisites are:

* **SSH admin access is required** - Ubuntu-secure runs as a shell script on the terminal.
* **A Ubuntu One account is recommended** - Canonical offers a livepatch service, which is free for personal use up to 3 machines. You can register at [this][livepatch] site. Once registered you get a token linked to your account.

## Deployment
Deployment of *Ubuntu-secure* is a matter of cloning the GitHub repository. Login to your server via SSH first. Assuming you are in the working folder of your choice, clone the repository files. Git automatically creates a new folder `ubuntu-secure` and copies the files to this directory. Then change your current folder to simplify the execution of the shell script.

```console
git clone https://github.com/markdumay/ubuntu-secure.git
cd ubuntu-secure
```

<!-- TODO: TEST CHMOD -->

## Usage
*Ubuntu-secure* requires `sudo` rights. Use the following command to invoke *ubuntu-secure* from the command line.

```
sudo ./ubuntu-secure.sh [OPTIONS] COMMAND
```

### Commands
*Ubuntu-secure* supports the following commands. 

| Command       | Argument  | Description |
|---------------|-----------|-------------|
| **`init`**    |           | Hardens a mint Ubuntu 20.04 LTS server |

The `init` command  executes the following sequence of steps.
* **A) Create a Non-Root User with Sudo Privileges** - Creates a non-root user `admin` with administrative privileges.
* **B) Disable Remote Root Login** - Ensures `root` can no longer login remotely to the server. Instead, the `admin` user with explicitly elevated privileges through `sudo` is used for server administration.
* **C) Secure Shared Memory** - Mounts `/run/shm` in read-only mode, preventing the ability of data being passed between applications.
* **D) Make Boot Files Read-Only** - Prevents unauthorized modifications to the server boot files.
* **E) Install Fail2Ban** - Prevents brute-force attacks by banning repeat login attempts from a single IP address.
* **F) Enable Livepatch** - If `CANONICAL_TOKEN` is specified in `.env`, automatically applies critical kernel security fixes without rebooting.
* **G) Enable Firewall** - Installs Uncomplicated Firewall (UFW) to only allow web-traffic (port 80 and port 443) and SSH-traffic (port `IP_SSH_PORT`) to the server. If 'IP_SSH_ALLOW_HOSTNAME' is specified, a cron job is executed every 5 minutes to poll for the IP address associated with the hostname. SSH access is then resticted to this IP address only.

<!-- TODO: SSH keys -->


### Options
*Ubuntu-secure* supports the following options. 

| Option      | Alias       | Argument   | Description |
|-------------|-------------|------------|-------------|
| `-f`        | `--force`   |            | Force the installation and bypass compatibility checks |


## Contributing
1. Clone the repository and create a new branch 
    ```
    $ git checkout https://github.com/markdumay/ubuntu-secure.git -b name_for_new_branch
    ```
2. Make and test the changes
3. Submit a Pull Request with a comprehensive description of the changes

## Credits
*Ubuntu-secure* is inspired by the following blog articles:
* Vladimir Rakov - [How to Harden your Ubuntu 18.04 Server][hostadvice]
* Thomas @ euroVPS - [20 Ways to Secure Your Linux VPS so You Don’t Get Hacked][eurovps]

## Donate
<a href="https://www.buymeacoffee.com/markdumay" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/lato-orange.png" alt="Buy Me A Coffee" style="height: 51px !important;width: 217px !important;"></a>

## License
<a href="https://github.com/markdumay/ubuntu-secure/blob/master/LICENSE" alt="License">
    <img src="https://img.shields.io/github/license/markdumay/ubuntu-secure.svg" />
</a>

Copyright © [Mark Dumay][blog]



<!-- MARKDOWN PUBLIC LINKS -->
[ubuntu_url]: https://ubuntu.com
[livepatch]: https://ubuntu.com/livepatch
[hostadvice]: https://hostadvice.com/how-to/how-to-harden-your-ubuntu-18-04-server/
[eurovps]: https://www.eurovps.com/blog/20-ways-to-secure-linux-vps/


<!-- MARKDOWN MAINTAINED LINKS -->
<!-- TODO: add blog link
[blog]: https://markdumay.com
-->
[blog]: https://github.com/markdumay
[repository]: https://github.com/markdumay/ubuntu-secure.git