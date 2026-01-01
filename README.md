# AWS Cloud Resume Challenge - Infrastructure as Code

![AWS](https://img.shields.io/badge/AWS-232F3E?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Python](https://img.shields.io/badge/python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)

## 📖 Project Overview

This project is a serverless resume website deployed on AWS, fully provisioned using **Terraform**. It demonstrates a full-stack cloud architecture, integrating a static frontend with a serverless backend API and database.

**Live Demo:** [Click here to view my Cloud Resume](https://d3qj25z2nahdvu.cloudfront.net) *(Replace with your actual CloudFront URL)*

## 🏗️ Architecture

The infrastructure is built with a **Serverless First** mindset and managed 100% via Infrastructure as Code (IaC).

* **Frontend:**
    * **Amazon S3:** Hosts the static HTML/CSS/JS files.
    * **Amazon CloudFront:** Provides global Content Delivery Network (CDN) for low latency and HTTPS security.
* **Backend:**
    * **Amazon API Gateway (HTTP API):** Acts as the entry point for the frontend to communicate with the backend.
    * **AWS Lambda (Python 3.9):** Executes serverless compute logic to handle visitor counter updates.
    * **Amazon DynamoDB:** NoSQL database to store and persist the atomic visitor count.
* **Infrastructure:**
    * **Terraform:** Orchestrates the entire lifecycle of AWS resources (IAM roles, Policies, Buckets, Functions, APIs) and automates frontend code deployment.

## 🛠️ Tech Stack

* **Cloud Provider:** AWS (us-east-1)
* **IaC:** HashiCorp Terraform
* **Backend Runtime:** Python 3.9 (Boto3)
* **Database:** DynamoDB (On-Demand Capacity)
* **Frontend:** HTML5, CSS3, JavaScript (Vanilla)
* **Version Control:** Git & GitHub

## 🚀 Deployment

Prerequisites: AWS CLI configured and Terraform installed.

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/Zizo-Jo/The-Cloud-Resume-Challenge.git](https://github.com/Zizo-Jo/The-Cloud-Resume-Challenge.git)
    cd The-Cloud-Resume-Challenge
    ```

2.  **Initialize Terraform:**
    ```bash
    cd terraform
    terraform init
    ```

3.  **Deploy Infrastructure:**
    ```bash
    terraform apply
    # Type 'yes' to confirm
    ```

4.  **Automatic Upload:**
    Terraform is configured to automatically detect changes in `index.html` and upload the new version to S3 upon applying.

## 💡 Key Learnings

* **Infrastructure as Code:** Migrated from manual console management to full Terraform automation, ensuring reproducibility and eliminating configuration drift.
* **Security:** Implemented **Least Privilege Principle** for Lambda IAM roles and secured S3 buckets using CloudFront OAI/OAC concepts (via Bucket Policy).
* **CORS & API:** Solved Cross-Origin Resource Sharing challenges between the static frontend and the API Gateway.