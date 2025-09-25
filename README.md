# Solution Overview

This repository contains a PoC web server environment that is fully deployable to AWS by terraform.   The environment is configured such that:

- An application load balancer accepts HTTP traffic and forwards it to the application servers
- The application servers are not accessible to the internet
- The application servers are managed by an auto scaling group
- A managment server exists in the public subnet and is able to ssh to the application servers
- Security groups exist that permit:
  - a single host/network space to ssh to the management server
  - The alb can only be accessed on port 80, and the application servers can only be reached by the alb on port 80 and the management server on port 22

![network-diagram](images/coalfire.drawio.png)

# Deployment instructions

1. Clone this repository
    - `git clone git@github.com:MD4HASH/poc-coalfire.git`
2. Install [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) and the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
3. Authenticate to AWS by defining the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables.
    - `export AWS_ACCESS_KEY_ID=`
    - `export AWS_SECRET_ACCESS_KEY=`
4. Initialize terraform
    - `terraform init`
5. Run terraform plan and apply
    - `terraform plan`, `terraform apply`

# Operational instructions

- When terraform completes,it will output the variable `alb_dns_name.` Enter this in a web browser.  Ensure that the url starts with `http://` and is not automatically changed to `https://` by the browser.
- This role generates a TLS certificate in the /secrets directory.  
  - Ensure that this directory is in your .gitignore file.
  - from the root terraform directory, you can use this key to ssh to the management servers public ip:
  - ssh -i ./secrets/operator_key.pem x.x.x.x
- from the management server, you can also ssh to the application servers
