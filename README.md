# ☁️ The Cloud Resume Challenge (Terraform & AWS Edition)

[![Terraform](https://img.shields.io/badge/Terraform-v1.0+-purple?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Serverless-orange?logo=amazon-aws)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Python-3.12-blue?logo=python)](https://www.python.org/)
[![Status](https://img.shields.io/badge/Status-Live-green)](https://zihao-cv.site)


## 📖 Introduction

This project is my implementation of **The Cloud Resume Challenge**. It is a serverless resume website deployed on **AWS**, fully provisioned using **Infrastructure as Code (Terraform)**.

The site features a static HTML frontend with a dynamic **visitor counter**, powered by a Python-based serverless backend. The architecture prioritizes **security**, **cost-optimization**, and **automation**.

## 🏗️ Architecture

The infrastructure leverages a multi-cloud approach for optimal performance and security:

1.  **Frontend**: Hosted on **AWS S3** (private bucket) and distributed globally via **AWS CloudFront** (CDN).
2.  **Backend**: **AWS API Gateway** (HTTP API) triggers a **Lambda** function running **Python 3.12**.
3.  **Database**: **AWS DynamoDB** stores visitor counts using atomic updates to handle concurrency.
4.  **DNS & Security**: **Cloudflare** manages DNS, providing DDoS protection and strict SSL/TLS encryption.
5.  **IaC**: **Terraform** manages the entire lifecycle of AWS resources using modular design.

## 🛠️ Tech Stack

| Category | Technology | Usage |
| :--- | :--- | :--- |
| **IaC** | **Terraform** | Provisioning (Modules & Environments) |
| **Compute** | **AWS Lambda** | Python 3.12 backend logic |
| **API** | **API Gateway** | HTTP API (v2) with CORS configuration |
| **Database** | **DynamoDB** | NoSQL storage (On-Demand billing) |
| **Storage** | **AWS S3** | Static website hosting (HTML/CSS/JS) |
| **CDN** | **CloudFront** | Global content delivery & HTTPS termination |
| **Security** | **AWS ACM** | SSL/TLS Certificate management |
| **DNS** | **Cloudflare** | DNS resolution & Edge caching |
| **Language** | **Python** | Backend logic (Boto3) |

## 📂 Project Structure

The project follows a modular architecture, separating environments (`dev`, `prod`) from reusable logic (`modules`).

```bash
.
├── envs/                   # Environment-specific configurations
│   ├── dev/                # Development environment (Entry point)
│   │   ├── main.tf         # Instantiates modules for Dev
│   │   ├── outputs.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod/               # Production environment
│       └── ...
├── modules/                # Reusable Terraform Modules
│   ├── backend/            # Lambda, DynamoDB, API Gateway resources
│   └── frontend/           # S3, CloudFront, ACM resources
├── src/                    # Source Code
│   ├── lambda/
│   │   └── func.py         # Python backend logic
│   └── website/
│       └── index.html      # Frontend HTML
├── .gitignore              # Git ignore rules (Crucial for security)
└── README.md               # Documentation
