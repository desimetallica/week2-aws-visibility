# Terraform Security Modules

This repository provides a comprehensive demonstration of foundational AWS security practices using Terraform and Ansible. The primary security objective is to establish secure-by-default AWS environments through automated provisioning of logging, monitoring, and least-privilege IAM controls. The report analyzes key cloud threats, including authentication and identity abuse, IAM privilege escalation, and defense evasion tactics such as log deletion. 

By combining infrastructure-as-code modules and practical log analysis techniques, this repo demonstrates how to detect, investigate, and mitigate common AWS security risks, supporting both prevention and incident response.

The following chapters are organized to cover the three main Terraform modules for AWS security in this workspace, log analysis and Lesson Learned:
- **terraform-security-baseline**
- **Analyse CloudTrail Logs (A deep analysis of attack patterns)**
- **terraform-security-config**
- **terraform-security-iam-baseline**
- **Lesson Learned**


## terraform-security-baseline

Sets up foundational AWS security resources, such as S3 buckets for CloudTrail logs and related policies.

### Features
- Creates an S3 bucket for CloudTrail logs
- Applies secure bucket policies and ACLs
- Parameterized for region and bucket name

### Usage
1. Edit `defaults.tfvars` to set your region and S3 bucket name.
2. Run:
   ```sh
   terraform init
   terraform apply -var-file=defaults.tfvars
   ```
3. Download logs from s3 bucket:
   ```
   aws s3 sync s3://desirellod-ct-logs/AWSLogs/your-account-number-id/CloudTrail/eu-south-1/2025/12/19/ ./cloudtrail-logs
   ```
4. Cleanup:
   ```sh
   terraform destroy -var-file=defaults.tfvars
   ```

## Analyse CloudTrail Logs
Reviewing CloudTrail logs for anomaly detection, these patterns actually matter during real incidents: 
- **Authentication & identity abuse**, 
- **IAM privilege escalation**, 
- **AccessDenied and Success correlation**, 
- **Defense Evasion and DeleteTrail**, 
- **Controlling security group modifications ModifySecurityGroup**,  

### Authentication & identity abuse

AWS compromises starts from credential theft usually, not exploits. The event to check in logs are the ones related to Login and Roles.
In AWS, authentication abuse usually falls into four concrete scenarios:
1. Stolen credentials (password or access key)
2. Session hijacking (temporary credentials abused)
3. Role misuse (unexpected AssumeRole)
4. Federation abuse (SSO / SAML / WebIdentity)

Core authentication-related CloudTrail events are: ConsoleLogin, AssumeRole, Federation events and GetSessionToken.

**ConsoleLogin**: check for MFAUsed = no, or login from new IPs or login at odd hours, it is important to check for patterns like Multiple failures and success, it means Password Guessing patterns.
A useful jq filter to use in this case:

```
jq '.Records[]
 | select(.eventName=="ConsoleLogin")
 | {
   time:.eventTime,
   user:.userIdentity.userName,
   ip:.sourceIPAddress,
   mfa:.additionalEventData.MFAUsed
 }'
```

**AssumeRole**: it's important to check because roles often are over-permissive and password is not needed. AssumeRole from IAM users or unexpected IPs and also Role Chaining are important pattern to check and could represent risk patterns. 
A useful jq filter to use in this case:

```
jq '.Records[]
 | select(.eventName=="AssumeRole")
 | {
   time:.eventTime,
   caller:.userIdentity.arn,
   role:.requestParameters.roleArn,
   ip:.sourceIPAddress
 }'
```

**Federation Events and GetSessionToken**: when using IAM Identity Center or OIDC the EventName to watch are:

- AssumeRoleWithSAML
- AssumeRoleWithWebIdentity
- Authenticate

Same patterns to check: unsual login hours or new IPs. The GetSessionToken returns a set of temporary credential for an AWS account or IAM user, often used to bypass MFA, is important to check human-user calling GetSessionToken and API usage from new IP pattern in this case.  
A usuelful jq filter to use in this case:

```
jq '.Records[]
 | select(.eventName=="ConsoleLogin" or .eventName=="AssumeRole" or .eventName=="AssumeRoleWithSAML" or .eventName=="AssumeRoleWithWebIdentity" or .eventName=="Authenticate")
 | {time:.eventTime, event:.eventName, user:.userIdentity.arn, ip:.sourceIPAddress}'

```

**Checking IPs**: a first way to check logins to AWS is to check IPs login could be done with

```
jq -r '.Records[].sourceIPAddress' *.json | sort | uniq -c | sort -nr
```

AWS internal usage could be ignored, lower IPs counts worth checking.

### IAM privilege escalation

IAM privilege escalation is the part of incidet where attackers must go through to persist and expand control. Some way on IAM privilege escalation looks like are related to concrete ways:

1. Attaching managed policies
2. Creating inline policies
3. Creating/rotating access keys
4. Abusing AssumeRole
5. Group membership abusing

With CloutTrail is possibile to record and check those type of events.

**Attaching managed policies**: attacching an Admin user policy like Administrator is what looking for. High-risk IAM events escalation indicators are:

- AttachUserPolicy
- AttachRolePolicy
- AttachGroupPolicy 
- PutUserPolicy
- PutRolePolicy
- PutGroupPolicy
- CreateAccessKey
- UdateAccessKey
- UpdateAssumeRolePolicy

**AttachUserPolicy/AttachRolePolicy/AttachGroupPolicy**: usually is related to an incident if outside normal usage, or if not planned, in example if AdministratorAccess or PowerUserAccess policy is attached could be an incident.

**PutUserPolicy/PutRolePolicy/PutGroupPolicy**: usually inline policies do not show up in IAM console summaries. You must look for wildcard like "Action": "*", "resource": "*" and "Effect": "Allow"

**CreateAccessKey/UpdateAccessKey**: access key creation and persistance mechanism is used to gain a persisting vector. Looking for key creation and then heavy API usage pattern as a bad pattern.

**UpdateAssumeRolePolicy**: this is used to expand the access scope of attacker by adding AWS Account User or service to the trust policy of an existing IAM role. Next to this the attacker can assume role escalating privileges withint environment  

**AddUserToGroup**: adding user to a group is classic way to privilege-escalation. It is critical because an attacker could escalade privileges without attacching policies bypassing AttachUserPolicy and PutUserPolicy.

**Management and Mitigation**

* Limit IAM identity creation privileges
* Enforce short-lived credentials
* Regularly audit IAM users, roles, and keys


---

### AccessDenied and Success correlation

AccessDenied and Success correlation is a good indicator to check a real attacker behavior in general. THe pattern usually follows those steps:
- Reconnaissance with denied calls
- Followed by role assumption or permission pivot
- Then successful enumeration

THe Time-window correlation is an important factor to consider when checking for this kind of relationship. A good rule could be:
- 1-5 miuntes: human escalation
- <30 seconds: scripted attack
- 1 hour: maybe legit admin activity

The detection of AccessDenied and Success correlation its important. AccessDenied tell you the intent, Success tells you the capability, Intent + capability means compromising. 
In "manual mode" you can find denied actions from CloudTrail logs:
```
jq -r '.Records[]
 | select(.errorCode=="AccessDenied")
 | "\(.userIdentity.arn)|\(.eventName)"' *.json \
 | sort | uniq
```

Extract output like 

```
arn:aws:iam::137809406849:user/carol|AttachUserPolicy
```

Next step is to find later success for same actor and action:  

```
jq '.Records[]
 | select(.userIdentity.arn=="arn:aws:iam::123:user/bob")
 | select(.eventName=="AttachUserPolicy")
 | select(.errorCode==null)
 | {
   time:.eventTime,
   params:.requestParameters
 }' *.json
```

### Defense Evasion and DeleteTrail

Defense evasion actions include all techniques aimed at avoiding detection and understanding the defender's reactions. Studying and monitoring defense evasion is essential to strengthen the security posture.

CloudTrail is a critical security control and must be protected against tampering. Actions such as DeleteTrail, StopLogging, and UpdateTrail can be abused to suppress or redirect audit logs after a compromise, reducing detection and forensic visibility. To preserve log integrity, these actions should be explicitly denied at the AWS Organizations SCP level, allowing exceptions only for a tightly controlled break-glass role. All CloudTrail trails should be organization-wide, multi-region, and configured to deliver logs to a central, immutable S3 bucket with MFA Delete and restricted write access. Any attempt to invoke these actions must be immediately alerted on via SIEM or CloudTrail Lake, as they represent high-confidence indicators of defense evasion rather than routine operations.

Often, during the defense evasion phase, the attacker tries to hide their tracks, but in the stress of incident response, the defender may make mistakes that the attacker can exploit to gain further attack vectors. A well-prepared defender implements tools such as honeypots to mislead the attacker and observe their TTPs (Tactics, Techniques, and Procedures), while it is crucial that the defender does not leave useful traces for the attacker. In general, a well-structured SIEM (such as Splunk) effectively manages these situations, enabling rapid monitoring and response to defense evasion actions.

**Monitoring and alerting on DeleteTrail and risky actions:**
- Continuously monitor events such as `DeleteTrail`, `StopLogging`, `UpdateTrail`.
- Generate immediate alerts on these events via SIEM.
- Use honeypots and trap logs to identify evasion attempts.
- Correlate suspicious actions with other indicators of compromise.
- AWS Config rules enforcing CloudTrail and logging configurations

**Management and Mitigation**

* Deny logging modifications via SCPs
* Centralize logs in immutable S3 buckets
* Trigger immediate alerts on any logging configuration changes


### Controlling security group modifications ModifySecurityGroup

Security Group modifications (AuthorizeSecurityGroupIngress/Egress, RevokeSecurityGroup*) have immediate security impact and are a common technique to expose workloads, enable lateral movement, or bypass perimeter controls after a compromise. To reduce risk, these actions should be restricted via SCPs and IAM policies, permitting changes only through approved infrastructure-as-code pipelines or tightly scoped operational roles. Ingress rules allowing 0.0.0.0/0 or ::/0, especially on administrative or database ports, must be treated as high-risk events and continuously monitored. All Security Group changes should be logged via CloudTrail and correlated with VPC Flow Logs in a SIEM, as unauthorized or anomalous modifications are strong indicators of post-compromise exploitation rather than normal configuration activity.

**Threat**
Unauthorized network configuration changes expose resources or enable lateral movement within the environment.

**Detection**

* CloudTrail monitoring of Security Group modifications
* AWS Config rules detecting open ingress (`0.0.0.0/0`, `::/0`)
* Correlation of Security Group changes with VPC Flow Logs

**Management and Mitigation**

* Restrict network changes to approved infrastructure-as-code pipelines
* Automatically remediate overly permissive rules
* Enforce network segmentation and least-access principles


## terraform-security-config

Deploys AWS Config resources for security guardrail and resource change tracking.

### Features
- Creates an S3 bucket for AWS Config logs
- Sets up secure policies for Config delivery
- Parameterized for region and bucket name
- Add custom config rule: iam_password_policy cloudtrail_enabled and s3_bucket_public_read_prohibited.

### Usage
1. Edit `defaults.tfvars` to set your region and S3 bucket name for Config.
2. Run:
   ```sh
   cd terraform-security-config/
   terraform init
   terraform apply -var-file=defaults.tfvars
   ```
3. Cleanup:
   ```sh
   terraform destroy -var-file defaults.tfvars
   ```

AWS Config is adopted as a security guardrail, not as a compliance or reporting-only service. Its primary purpose is prevention: stopping insecure configurations from persisting long enough to become exploitable. Compliance status is a by-product, not the goal. Each AWS Config rule exists to enforce a security boundary and to reduce a clearly defined risk within the AWS environment.

### Risk-Driven Rule Design
Every AWS Config rule must be directly mapped to a specific mitigated risk (for example: public network exposure, excessive IAM privileges, disabled logging, or unencrypted storage). Rules are not created to satisfy generic standards alone; they are implemented to block real attack paths. For this reason, each rule must have an explicit security rationale that explains what threat it mitigates and why that configuration is considered unsafe.

### Meaning of Non-Compliant Resources
A resource marked as non-compliant represents an active security condition, not an informational finding. Non-compliance must clearly describe:
- the insecure configuration that was detected,
- the risk introduced by that configuration,
- the concrete action required to restore compliance.
If a rule cannot guide an operator toward a specific remediation, it is considered incomplete and unsuitable for use as a guardrail.

### Prevention Through Automation and Enforcement
AWS Config becomes an effective preventive control when combined with automated remediation, Service Control Policies (SCPs), and infrastructure-as-code enforcement. SCPs are used to prevent high-risk configurations from being introduced in the first place, while CI/CD pipelines ensure that infrastructure changes comply with Config rules before deployment.

### Operational Integration and Monitoring
All AWS Config findings must be integrated with centralized monitoring and alerting systems. High-risk non-compliance events should generate immediate alerts and be correlated with CloudTrail and other telemetry sources. This ensures that misconfigurations are treated as potential security incidents and not deferred as routine configuration drift.

**Guiding Principle**: The guiding principle is simple: AWS Config defines what “secure by default” means in this environment. Any deviation from those rules is treated as a security issue that requires timely remediation. By designing Config rules around risk, actionability, and enforcement, AWS Config serves as a foundational control for maintaining a defensible and resilient cloud posture. 

### Data Exposure and Exfiltration mitigation
One important AWS Config rule is designed to identify and prevent unintended data exposure by continuously evaluating the configuration of data storage resources within the AWS environment. It focuses on detecting misconfigurations or sharing settings that could allow unauthorized access to data stored in services such as **Amazon S3**, databases, snapshots, or backups. The rule supports early detection, compliance enforcement, and risk reduction by integrating with AWS-native monitoring and security services. 
**Threat**
Unauthorized access to or exposure of data stored in S3, databases, snapshots, or backups.

**Detection**

* AWS Config rules detecting public or shared resources (S3_BUCKET_PUBLIC_READ_PROHIBITED rule)
* CloudTrail monitoring for snapshot and bucket sharing (CLOUD_TRAIL_ENABLED rule)

**Management and Mitigation**

* Block public access by default
* Encrypt data at rest and in transit
* Restrict and monitor cross-account sharing

## terraform-security-iam-baseline

Establishes a baseline IAM configuration for secure, role-based access control.

### Features
- Creates three IAM groups: admins, developers, readonly
- Attaches tailored policies to each group
- Creates one user per group (default: alice, bob, carol)
- Assigns users to their respective groups
- Enables AWS Console login for the readonly user (carol), with password output and login URL

### Usage
1. Edit `defaults.tfvars` to customize user/group names or region if needed.
2. Run:
   ```sh
   terraform init
   terraform apply -var-file=defaults.tfvars
   ```
3. After apply, retrieve the console login URL and initial password for carol:
   ```sh
   terraform output carol_console_login_url
   terraform output carol_console_password
   ```
4. Cleanup:
   ```sh
   terraform destroy -var-file defaults.tfvars
   ```

### Importance of IAM Usage in AWS

The scope of AWS IAM defines is to  **who can access resources and what actions they are allowed to perform**, moreover the real purpose goes beyond organization of users and groups. A well-defined IAM model and baseline exist primarily to **prevent abuse**, not just to order the things. By enforcing least privilege, separating roles across distinct groups (such as developers, infrastructure, and security), and eliminating unnecessary permissions, IAM limits the blast radius of compromised credentials, insider misuse, and operational mistakes. This role separation ensures that no single identity can be easily abused to perform unintended actions, even under incident-response pressure or automation failures. As a result, the IAM baseline becomes a defensive control that contains risk, improves auditability, and strengthens the overall security posture of the AWS environment.


---

## Lessons Learned

- Cloud trail basic configuration.
- Cloud trail basic analysis both from dashboard and downloading logs.
- Parameterizing security resources in Terraform makes the configuration reusable and secure.
- AWS config hands on on policies and security patterns to adopt on AWS landing zone.
- tested Simple rules and checked compliancy into dashboard.
- Always test user login and permissions to ensure least-privilege access is enforced.
- Sensitive outputs (like passwords) should be handled carefully to avoid credential leaks.
- AWS password policies may block password changes if not met—set a compliant policy in the AWS Console.
- Documenting security baselines helps with onboarding and compliance.
