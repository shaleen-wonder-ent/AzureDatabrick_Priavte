## Architecture Diagram

```mermaid
graph TB
    subgraph "Azure Central India Region"
        subgraph "Resource Group: rg-databricks-private-india"
            subgraph "Virtual Network 10.0.0.0/16"
                subgraph "Databricks Subnets"
                    DBHost[Databricks Host<br/>10.0.1.0/24<br/>Driver Nodes]
                    DBContainer[Databricks Container<br/>10.0.2.0/24<br/>Executor Nodes]
                end
                
                subgraph "Private Endpoints Subnet 10.0.3.0/24"
                    PEUI[PE-Databricks-UI-API]
                    PEAuth[PE-Databricks-Auth]
                    PEBlob[PE-ADLS-Blob]
                    PEDFS[PE-ADLS-DFS]
                end
                
                subgraph "Access Subnets"
                    JumpVM[Jump VM<br/>10.0.5.0/24]
                    Bastion[Azure Bastion<br/>10.0.6.0/26]
                end
            end
            
            subgraph "Azure Services"
                DB[Databricks Workspace<br/>Premium SKU]
                ADLS[ADLS Gen2 Storage<br/>Private Access Only]
                DNS[Private DNS Zones]
            end
        end
    end
    
    subgraph "External Access"
        User[Admin User]
        Portal[Azure Portal]
    end
    
    User --> Portal
    Portal --> Bastion
    Bastion -.->|RDP/SSH| JumpVM
    JumpVM -.->|HTTPS| PEUI
    PEUI -.->|Private Link| DB
    DB -.->|Private Link| DBHost
    DB -.->|Private Link| DBContainer
    DBHost -.->|Private Endpoint| PEBlob
    DBContainer -.->|Private Endpoint| PEDFS
    PEBlob -.->|Azure Backbone| ADLS
    PEDFS -.->|Azure Backbone| ADLS
    
    style User fill:#f9f,stroke:#333,stroke-width:2px
    style Portal fill:#bbf,stroke:#333,stroke-width:2px
    style Bastion fill:#fbf,stroke:#333,stroke-width:2px
    style JumpVM fill:#bfb,stroke:#333,stroke-width:2px
    style DB fill:#ff9,stroke:#333,stroke-width:2px
    style ADLS fill:#9ff,stroke:#333,stroke-width:2px
