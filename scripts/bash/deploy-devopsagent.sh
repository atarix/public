#!/bin/bash

set -e

# Check if all parameters are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <ORG_URL> <POOL_NAME> <PAT_TOKEN> <AGENT_NAME>"
    exit 1
fi

ORG_URL=$1
POOL_NAME=$2
PAT_TOKEN=$3
AGENT_NAME=$4
AGENT_VERSION_URL="https://download.agent.dev.azure.com/agent/4.258.1/vsts-agent-linux-x64-4.258.1.tar.gz"
INSTALL_DIR="/opt/azure/devops/agent"

echo "Starting Azure DevOps agent setup..."

# Update package lists
echo "Updating package lists..."
sudo apt-get update -y

echo "Installing dependencies..."
sudo apt-get install -y libcurl4 openssl jq

# Install Git
echo "Installing Git..."
sudo apt-get update
sudo apt-get install -y git

# Install Azure CLI
echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Bicep CLI
echo "Installing Bicep CLI..."
az bicep install

# Install PowerShell
echo "Installing PowerShell..."
# Import the public repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Install PowerShell commandlets
echo "Installing PowerShell commandlets..."
sudo apt-get update
sudo apt-get install -y powershell

# Install powershell-yaml module
echo "Installing powershell-yaml module..."
pwsh -Command "Install-Module -Name powershell-yaml -Force -Scope AllUsers"

# Install SQL Server module
echo "Installing sqlserver module..."
pwsh -Command "Install-Module -Name sqlserver -RequiredVersion 22.2.0 -Force -Scope AllUsers"

# Install Azure DevOps Agent
# Create a directory for the agent
echo "Creating installation directory at $INSTALL_DIR..."
sudo mkdir -p $INSTALL_DIR
sudo chown $(whoami):$(whoami) $INSTALL_DIR

echo "Creating dedicated user 'azuredevops'..."
sudo useradd -m -d $INSTALL_DIR -s /bin/bash azuredevops || echo "User 'azuredevops' already exists."

# Download the latest agent package
echo "Downloading Azure DevOps agent from $AGENT_VERSION_URL..."
wget -O agent.tar.gz $AGENT_VERSION_URL

# Extract the agent package
echo "Extracting the agent to $INSTALL_DIR..."
tar -zxvf agent.tar.gz -C $INSTALL_DIR
rm agent.tar.gz

# Configure the agent
echo "Configuring the Azure DevOps agent..."
cd $INSTALL_DIR
chmod +x ./config.sh
sudo chown -R azuredevops:azuredevops $INSTALL_DIR
su - azuredevops -c "./config.sh \
    --unattended \
    --agent $AGENT_NAME \
    --url $ORG_URL \
    --pool $POOL_NAME \
    --auth PAT \
    --token $PAT_TOKEN \
    --acceptTeeEula \
    --replace"

echo "Agent configured successfully."

if [ $? -ne 0 ]; then
    echo "Error during agent configuration. Displaying log file:"
    cat /opt/azure/devops/agent/_diag/Agent_$(date +%Y%m%d)-*.log
    exit 1
fi

# Install dependencies
sudo ./bin/installdependencies.sh

# Install the agent
echo "Installing the agent as a service..."
chmod +x ./svc.sh
sudo ./svc.sh install

# Start the agent service
echo "Starting the agent service..."
sudo ./svc.sh start

echo "Azure DevOps agent setup completed successfully."

