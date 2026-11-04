MidPoint 4.12.0 Development Branch
-------------------------------

General information:

MidPoint is a comprehensive Identity Governance and Administration (IGA) platform. It is used by the organizations around the world to deal with Identity Provisioning, Identity Governance & Compliance and also Access Management. As for the identity being a security perimeter, midPoint keeps safe both organization’s internal network and external resources.
The most important features of midPoint are:

- Identity Governance
- Security auditing and reporting
- Organizational structure management
- Credential Management
- Request approval
- Entitlement Management

Read more about these features at https://evolveum.com/midpoint/

Other features:

- User provisioning and deprovisioning
- Administration GUI
- Identity repository implementation (SQL)
- Custom schema extensibility
- Identity synchronization (liveSync, reconciliation, discovery, import)
- Support for expressions in synchronization mappings (mainly via MidPoint Expression Language)
- Advanced RBAC support with temporal constraints
- Identity management process automation (workflow, notifications)
- Password policies
- Password reset
- Entitlements
- Archetypes
- Support for ConnId connectors
- Provisioning consistency and error handling
- Data protection (experimental)
- Reporting
- Notifications
- Local Java APIs, Remote web service interface (SOAP), REST API
- High availability (HA) support
- Rapid application onboarding with the help of AI

For more information about midPoint identity manager please go to:
https://midpoint.evolveum.com/

For bugtracking system please go to:
https://support.evolveum.com/

MidPoint source code is maintained on github:
https://github.com/Evolveum/midpoint

Latest source code can be obtained from our Git repository using one of the
following repository locations:
https://github.com/Evolveum/midpoint.git

git@github.com:Evolveum/midpoint.git

This project is licensed under European Union Public License. The documentation is licensed under
the terms of Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International (CC BY-NC-ND 4.0) license.
See LICENSE file for details.

## Adyaka Branding Overlay

This fork includes a zero-OOTB-modification branding overlay for **Adyaka Infosec** under `branding/adyaka/`.

### Quick Start (Docker)

```bash
docker compose -f branding/adyaka/docker-compose.yml up -d --build
```

Open: http://localhost:8082/adyaka  
Login: `administrator` / `Adyaka@2024!`

### Quick Start (Local Server)

Prerequisites: Java 17+, PostgreSQL 16

```bash
# One-time DB setup
psql postgres -c "CREATE USER adyaka WITH PASSWORD 'adyaka.db.secret';"
psql postgres -c "CREATE DATABASE adyaka OWNER adyaka;"

# Deploy and start
./branding/adyaka/deploy.sh start
```

See [branding/adyaka/BRANDING.md](branding/adyaka/BRANDING.md) for full documentation.
