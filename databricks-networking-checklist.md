# Databricks Networking Best Practices Checklist

A decision checklist for securing Azure Databricks workspace networking. Each item includes the recommended action and the rationale behind it.

---

## Workspace Isolation

- [ ] **Use Premium tier + VNet Injection + SCC/NPIP for workspaces requiring strong classic-compute isolation**
  - *Rationale:* Secure Cluster Connectivity (SCC) removes public IPs from classic compute nodes, eliminating direct inbound access. SCC depends on VNet injection, and for existing workspaces this is the documented upgrade path. NPIP (No Public IP) is the equivalent setting — together they ensure classic nodes have no public-facing network interfaces.

## Private User Access

- [ ] **Enable front-end Private Link, create the `browser_authentication` endpoint, and set Public network access = Disabled**
  - *Rationale:* This implements the Databricks-documented "private-only user access" model. Without the `browser_authentication` endpoint, AAD login flows break because the browser redirect has no private path. Disabling public access ensures no user traffic traverses the public internet.

- [ ] **Create a dedicated private web auth workspace per region for production**
  - *Rationale:* The web auth workspace handles browser authentication redirects for all private workspaces in a region. It should be isolated: disable public access, do not run workloads on it, do not create a `databricks_ui_api` endpoint on it, and apply a delete lock. This prevents accidental deletion from breaking authentication for all dependent workspaces.

## Classic Compute Plane Connectivity

- [ ] **Add back-end Private Link and set workspace networking to `NoAzureDatabricksRules`**
  - *Rationale:* Back-end Private Link routes control plane to compute plane traffic over the Microsoft backbone instead of the public internet. The `NoAzureDatabricksRules` setting is the Databricks-documented configuration for complete private isolation of classic compute — it removes the default Azure Databricks managed NSG rules that allow public connectivity.

## Network Topology

- [ ] **Use a Hub-and-Spoke architecture**
  - *Rationale:* A transit (hub) VNet centralizes inbound private endpoints, private DNS, Private Resolver, and optionally Azure Firewall. A separate spoke VNet holds Databricks subnets and classic private endpoints. This separation of concerns simplifies management, enables shared services, and follows Azure's recommended landing zone pattern.

## PaaS Service Connectivity

- [ ] **Prefer private endpoints over service endpoints as the default standard**
  - *Rationale:* Service endpoints route traffic over the Azure backbone but the service addresses remain publicly routable — they don't satisfy on-prem or private-only requirements. Private endpoints assign a private IP from your VNet, making the service fully resolvable and reachable over private networks only.

- [ ] **For classic compute, use private endpoints with public access disabled on all PaaS dependencies**
  - *Rationale:* ADLS/Blob, SQL, Key Vault, Event Hubs, Cosmos DB, and other PaaS services should be locked down to private endpoint access only. Disabling public access ensures that even if a private endpoint misconfiguration occurs, the service rejects connections from outside the private network.

## Serverless Compute Connectivity

- [ ] **Use NCC-managed private endpoints for supported resources and enable restricted egress policies**
  - *Rationale:* Network Connectivity Configurations (NCC) are the Databricks-managed mechanism for serverless private connectivity. Restricted egress policies add an allowlist layer so that even traffic flowing through private endpoints is governed — preventing data exfiltration to unauthorized destinations.

- [ ] **Use serverless Private Link to a Standard Load Balancer / Private Link Service for internal VNet services**
  - *Rationale:* Rather than exposing internal services publicly so serverless compute can reach them, create a Private Link Service backed by a Standard Load Balancer. Serverless compute connects via private endpoint, keeping internal services completely unexposed to the internet.

## DNS

- [ ] **Use Azure Private DNS Zones + Azure Private Resolver and treat DNS as part of the security boundary**
  - *Rationale:* Private endpoints only work if DNS resolves the service FQDN to the private IP rather than the public one. Azure Private DNS Zones provide this resolution within Azure, and Private Resolver (or equivalent forwarders) extends it to on-premises networks. Without proper DNS, clients silently fall back to public IPs, undermining the entire private networking setup.

## Outbound Internet Connectivity

- [ ] **Attach a NAT Gateway to both workspace subnets if allowing direct outbound internet (without force tunneling)**
  - *Rationale:* NAT Gateway provides stable, predictable egress IPs — important for allowlisting with external services. It also aligns with Azure's post-March 31, 2026 change that removes default outbound connectivity for new VNets. Without NAT Gateway (and without force tunneling), new VNets will have no outbound internet access.

- [ ] **If force tunneling 0.0.0.0/0 to Azure Firewall or an NVA, understand that NAT Gateway does not apply**
  - *Rationale:* When a 0/0 UDR directs traffic to a firewall or network virtual appliance, that device handles all internet-destined traffic — NAT Gateway is bypassed entirely. This is a common misconfiguration: teams deploy both NAT Gateway and a 0/0 UDR, expecting NAT Gateway to provide stable IPs, but the UDR takes precedence.

## Firewall and NSG Rules

- [ ] **Use Azure service tags where Databricks documents them, and allowlist SCC relay FQDNs instead of IPs**
  - *Rationale:* Service tags are maintained by Microsoft and automatically update as IP ranges change. SCC relay endpoints should be allowlisted by FQDN because the underlying IPs can change without notice — hardcoding IPs creates fragile rules that break silently.

- [ ] **Keep Databricks-managed NSG rules intact, use a unique NSG per workspace, and add deny rules for same/peered VNets**
  - *Rationale:* Databricks-managed NSG rules are required for cluster operation — modifying them causes cluster launch failures. A unique NSG per workspace prevents rule conflicts between workspaces. Adding explicit deny rules for peered VNets ensures Databricks subnets only reach intended destinations, implementing least-privilege network access.

## Legacy Feature Migration

- [ ] **Do not start new designs on the legacy serverless firewall feature**
  - *Rationale:* Microsoft has announced that the legacy serverless firewall feature reaches end of life after April 7, 2026. Customers must migrate to the new Network Security Perimeter (NSP) model. Building on a deprecated feature creates technical debt and a forced migration under time pressure.

---

*Generated from networking best practices notes. Review and adapt to your specific environment and compliance requirements.*
