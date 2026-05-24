This repository provides multiple automation scripts to build a small Active Directory environment for penetration testing practice. 
Each script corresponds to a specific virtual machine, so you can run exactly what you need - whether it’s a Domain Controller, member server, or workstation. 
This way, you can experiment with one machine at a time or create a more complex network.

To get started, clone the repo, place your Windows ISO files in the same directory, and run the scripts in the order that makes sense for your setup. 
For example, you might deploy the Domain Controller first, then add a web server or a workstation. 
Each script performs all the necessary configuration steps such as installing roles, creating users, and enabling intentional vulnerabilities. 
Once the scripts finish, you’ll have an environment ready to explore real-world lateral movement, privilege escalation, and other AD-centric attacks.

Keep in mind that this lab is intentionally insecure, so it should never be exposed on a production or public network. 
It’s meant purely for local testing and educational purposes. 
If anything fails during setup, it’s often due to missing ISO files, insufficient resources, or antivirus interference. 
Feel free to adapt the scripts to your hypervisor of choice, as they’ve primarily been tested on VMware. 
If you have suggestions or want to add more scripts, open an issue or submit a pull request. 
You can also view detailed setup and exploitation instructions on my website: https://lobenstein.com
Have fun hacking in a safe space!
