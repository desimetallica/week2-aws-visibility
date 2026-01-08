# Terraform Security Modules

This documentation covers the three main Terraform modules for AWS security in this workspace:
- **terraform-security-baseline**
- **terraform-security-config**
- **terraform-security-iam-baseline**



## terraform-security-baseline

### Purpose
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

## Analyse CloudTrail Logs
Reviewing CloudTrail logs for anomaly detection, these patterns actually matter during real incidents.

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

 

## terraform-security-config

### Purpose
Deploys AWS Config resources for compliance and resource change tracking.

### Features
- Creates an S3 bucket for AWS Config logs
- Sets up secure policies for Config delivery
- Parameterized for region and bucket name
- Add custom config rule: iam_password_policy cloudtrail_enabled and s3_bucket_public_read_prohibited.

### Usage
1. Edit `defaults.tfvars` to set your region and S3 bucket name for Config.
2. Run:
   ```sh
   terraform init
   terraform apply -var-file=defaults.tfvars
   ```

---

## terraform-security-iam-baseline

### Purpose
Establishes a baseline IAM configuration for secure, role-based access control.

### Features
- Creates three IAM groups: admins, developers, readonly
- Attaches tailored policies to each group
- Creates one user per group (default: alice, bob, carol)
- Assigns users to their respective groups
- Enables AWS Console login for the readonly user (carol), with password output and login URL
- All group/user names and region are parameterized

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
