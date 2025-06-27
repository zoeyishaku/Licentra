# 🔐 Licentra - Digital Product Licensing Smart Contract

> Time-bound smart contracts for digital product usage licensing on Stacks blockchain

## 📋 Overview

Licentra is a decentralized digital product licensing system that enables creators to:
- 🎯 Create and manage digital products
- ⏰ Issue time-bound licenses with automatic expiration
- 💰 Set custom pricing per block duration
- 🔒 Control access and revoke licenses when needed
- 📊 Track revenue from license sales

## ✨ Features

- **Product Management**: Create, deactivate, and update pricing for digital products
- **Time-Based Licensing**: Purchase licenses with specific block duration
- **License Extension**: Extend existing licenses with additional time
- **Access Control**: Validate license status and remaining time
- **Revenue Tracking**: Monitor total earnings per product
- **License Revocation**: Product owners can revoke licenses when needed

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd Licentra
```

2. Install dependencies:
```bash
npm install
```

3. Deploy the contract:
```bash
clarinet deploy
```

## 📖 Usage Guide

### 🎨 Creating a Product

```clarity
(contract-call? .Licentra create-product 
  "My Digital Course" 
  "Complete web development course with 50+ hours of content" 
  u100) ;; 100 microSTX per block
```

### 🛒 Purchasing a License

```clarity
(contract-call? .Licentra purchase-license 
  u1      ;; product-id
  u1440)  ;; duration in blocks (~10 days)
```

### ⏳ Extending a License

```clarity
(contract-call? .Licentra extend-license 
  u1      ;; product-id
  u720)   ;; additional blocks (~5 days)
```

### 🔍 Checking License Status

```clarity
;; Check if license is currently valid
(contract-call? .Licentra is-license-valid 
  'SP1EXAMPLE... ;; user principal
  u1)           ;; product-id

;; Get remaining blocks
(contract-call? .Licentra get-license-remaining-blocks 
  'SP1EXAMPLE... ;; user principal
  u1)           ;; product-id
```

### 📊 Managing Products

```clarity
;; Update product pricing
(contract-call? .Licentra update-product-price u1 u150)

;; Deactivate product
(contract-call? .Licentra deactivate-product u1)

;; Revoke a specific license
(contract-call? .Licentra revoke-license u1)
```

## 🔧 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create-product` | Create a new digital product | name, description, price-per-block |
| `purchase-license` | Buy a time-bound license | product-id, duration-blocks |
| `extend-license` | Extend existing license | product-id, additional-blocks |
| `revoke-license` | Revoke a license (owner only) | license-id |
| `deactivate-product` | Deactivate product (owner only) | product-id |
| `update-product-price` | Update pricing (owner only) | product-id, new-price-per-block |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-product` | Get product details | Product info or none |
| `get-license` | Get license details | License info or none |
| `get-user-license` | Get user's license for product | License info or none |
| `is-license-valid` | Check if license is active | true/false |
| `get-license-remaining-blocks` | Get remaining license time | Number of blocks or none |
| `get-product-revenue` | Get total product revenue | Revenue amount |

## 💡 Use Cases

- 📚 **Educational Content**: Online courses, tutorials, e-books
- 🎮 **Gaming**: Time-limited game access, premium features
- 🛠️ **Software Tools**: SaaS applications, development tools
- 🎵 **Media Content**: Music streaming, video content
- 📱 **App Features**: Premium app functionalities

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 🛡️ Security Features

- ✅ Owner-only functions protected
- ✅ Input validation on all parameters
- ✅ Automatic license expiration
- ✅ Prevent double-licensing
- ✅ Secure payment handling

## 📝 Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only |
| u101 | Not found |
| u102 | Unauthorized |
| u103 | Already exists |
| u104 | Invalid duration |
| u105 | Insufficient payment |
| u106 | License expired |
| u107 | Invalid product |
| u108 | License revoked |

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co)
- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Clarinet Guide](https://github.com/hirosystems/clarinet)

---

