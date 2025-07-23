# BitCartel

A decentralized marketplace for digital goods built on the Stacks blockchain, enabling secure peer-to-peer transactions with built-in escrow and reputation systems.

## Overview

BitCartel is a trustless marketplace where buyers and sellers can trade digital goods like plugins, ebooks, code templates, and other digital assets using STX tokens. The platform features an automated escrow system, on-chain reputation scoring, and dispute resolution mechanisms.

## Features

- **Secure Escrow System**: Funds are held in smart contract until delivery confirmation
- **Reputation System**: On-chain ratings and transaction history for all users
- **Dispute Resolution**: Built-in arbitration system for transaction conflicts
- **Platform Fee**: Sustainable 2.5% fee structure for platform maintenance
- **Digital Goods Focus**: Optimized for plugins, ebooks, code, templates, and digital assets

## Smart Contract Functions

### Core Escrow Functions
- `create-escrow`: Create new escrow transaction with item hash
- `confirm-delivery`: Seller confirms item delivery with proof hash
- `complete-transaction`: Buyer releases funds to seller
- `dispute-transaction`: Initiate dispute for problematic transactions
- `resolve-dispute`: Admin function to resolve disputes

### Reputation Functions
- `rate-user`: Rate transaction counterpart (1-5 stars)
- `get-user-reputation`: View user's reputation metrics
- `get-user-average-rating`: Calculate average rating for user

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet configured
- Node.js and npm for frontend development

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/bitcartel.git
cd bitcartel
```

2. Install dependencies:
```bash
clarinet check
npm install
```

3. Run tests:
```bash
clarinet test
```

4. Deploy to testnet:
```bash
clarinet deploy --testnet
```

## Usage

### Creating an Escrow

```clarity
(contract-call? .bitcartel create-escrow 'SP1234...SELLER 1000000 0x1234...)
```

### Confirming Delivery

```clarity
(contract-call? .bitcartel confirm-delivery u1 0x5678...)
```

### Completing Transaction

```clarity
(contract-call? .bitcartel complete-transaction u1)
```

## Architecture

- **Escrow Management**: Secure fund holding with status tracking
- **Reputation System**: Aggregated ratings and transaction history
- **Dispute Resolution**: Admin-mediated conflict resolution
- **Fee Structure**: Sustainable platform economics

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

- All user inputs are validated and sanitized
- Proper error handling prevents contract exploitation  
- Funds are secured through battle-tested escrow patterns
- Regular security audits recommended for production deployment

