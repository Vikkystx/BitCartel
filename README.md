# BitCartel

A decentralized marketplace for digital goods built on the Stacks blockchain, enabling secure peer-to-peer transactions with built-in escrow, reputation systems, and multi-token support.

## Overview

BitCartel is a trustless marketplace where buyers and sellers can trade digital goods like plugins, ebooks, code templates, and other digital assets using STX tokens or any supported SIP-010 fungible tokens. The platform features an automated escrow system, on-chain reputation scoring, dispute resolution mechanisms, emergency refund protections, and flexible payment options.

## Features

- **Multi-Token Support**: Accept payments in STX or any whitelisted SIP-010 fungible tokens
- **Secure Escrow System**: Funds are held in smart contract until delivery confirmation
- **Reputation System**: On-chain ratings and transaction history for all users
- **Dispute Resolution**: Built-in arbitration system for transaction conflicts
- **Emergency Refunds**: Automatic refund mechanism for transactions older than 30 days
- **Platform Fee**: Sustainable 2.5% fee structure for platform maintenance
- **Digital Goods Focus**: Optimized for plugins, ebooks, code, templates, and digital assets
- **Token Management**: Admin controls for adding/removing supported tokens
- **Hash Verification**: Item and delivery hash validation for proof of goods/delivery

## Contract Architecture

### Data Structures

- **Escrows**: Core transaction records with buyer, seller, amount, status, and hash verification
- **User Reputation**: Total ratings, rating count, and completed transactions per user
- **Transaction Ratings**: Individual ratings per escrow and rater
- **Supported Tokens**: Whitelist of approved SIP-010 tokens with status tracking

### Status Types

- `STATUS-PENDING (0)`: Escrow created, awaiting delivery
- `STATUS-DELIVERED (1)`: Seller confirmed delivery, awaiting buyer confirmation
- `STATUS-COMPLETED (2)`: Transaction completed successfully
- `STATUS-DISPUTED (3)`: Transaction under dispute resolution
- `STATUS-REFUNDED (4)`: Funds returned to buyer

## Smart Contract Functions

### Core Escrow Functions

#### STX Escrow Management
- `create-escrow-stx(seller, amount, item-hash)`: Create new STX escrow transaction
- `complete-transaction-stx(escrow-id)`: Buyer releases STX funds to seller
- `resolve-dispute-stx(escrow-id, refund-to-buyer)`: Admin resolves STX disputes
- `emergency-refund-stx(escrow-id)`: Admin emergency refund for STX (30+ days old)

#### SIP-010 Token Escrow Management
- `create-escrow-sip010(seller, amount, item-hash, token-contract, token-name)`: Create SIP-010 token escrow
- `complete-transaction-sip010(escrow-id, token-contract)`: Buyer releases tokens to seller
- `resolve-dispute-sip010(escrow-id, refund-to-buyer, token-contract)`: Admin resolves token disputes
- `emergency-refund-sip010(escrow-id, token-contract)`: Admin emergency refund for tokens (30+ days old)

#### Universal Functions
- `confirm-delivery(escrow-id, delivery-hash)`: Seller confirms item delivery with proof hash
- `dispute-transaction(escrow-id)`: Either party can initiate dispute resolution

### Reputation System
- `rate-user(escrow-id, user, rating)`: Rate transaction counterpart (1-5 stars)
- `get-user-reputation(user)`: View user's complete reputation metrics
- `get-user-average-rating(user)`: Calculate average rating for user

### Read-Only Functions
- `get-escrow-details(escrow-id)`: Retrieve complete escrow information
- `get-escrow-count()`: Get total number of escrows created
- `get-platform-fee(amount)`: Calculate platform fee for given amount
- `get-platform-fee-rate()`: Get current platform fee rate (basis points)

### Token Management Functions
- `add-supported-token(token-contract, token-name)`: Admin function to whitelist SIP-010 tokens
- `toggle-token-status(token-contract)`: Admin function to enable/disable tokens
- `get-supported-token(token-contract)`: Check token details and status
- `is-token-supported(token-contract)`: Verify if token is currently supported

## Error Codes

- `ERR-NOT-AUTHORIZED (100)`: Unauthorized operation
- `ERR-INVALID-AMOUNT (101)`: Invalid transaction amount
- `ERR-ESCROW-NOT-FOUND (102)`: Escrow does not exist
- `ERR-ESCROW-ALREADY-EXISTS (103)`: Escrow or token already exists
- `ERR-INVALID-STATUS (104)`: Invalid escrow status for operation
- `ERR-INSUFFICIENT-FUNDS (105)`: Insufficient funds for operation
- `ERR-ALREADY-RATED (106)`: User already rated this transaction
- `ERR-INVALID-RATING (107)`: Rating must be between 1-5
- `ERR-SELF-RATING (108)`: Cannot rate yourself
- `ERR-INVALID-HASH (109)`: Invalid hash provided
- `ERR-TOKEN-TRANSFER-FAILED (110)`: Token transfer operation failed
- `ERR-UNSUPPORTED-TOKEN (111)`: Token not supported
- `ERR-TOKEN-NOT-FOUND (112)`: Token not found in registry
- `ERR-INVALID-TOKEN-NAME (113)`: Invalid token name format
- `ERR-INVALID-PARTY (114)`: User not party to this escrow

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

## Usage Examples

### Creating an STX Escrow

```clarity
;; Create escrow for 1 STX with item hash
(contract-call? .bitcartel create-escrow-stx 
    'SP1234567890ABCDEF1234567890ABCDEF12345678  ;; seller address
    u1000000                                      ;; 1 STX in microSTX
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12 ;; item hash
)
```

### Creating a SIP-010 Token Escrow

```clarity
;; Create escrow for 100 USDA tokens
(contract-call? .bitcartel create-escrow-sip010 
    'SP1234567890ABCDEF1234567890ABCDEF12345678  ;; seller address
    u100000000                                   ;; 100 USDA (assuming 6 decimals)
    0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef12 ;; item hash
    'SP2C2HDM2JCYNHFZN3V73KMWF8HQJJKQVXZS4TJR5.arkadiko-token ;; USDA contract
    "USDA"                                       ;; token name
)
```

### Seller Workflow

```clarity
;; 1. Wait for escrow creation by buyer
;; 2. Deliver digital goods
;; 3. Confirm delivery with proof hash
(contract-call? .bitcartel confirm-delivery 
    u1  ;; escrow ID
    0x5678901234abcdef5678901234abcdef5678901234abcdef5678901234abcdef56 ;; delivery hash
)
```

### Buyer Workflow

```clarity
;; 1. Create escrow with item hash
;; 2. Wait for seller delivery confirmation
;; 3. Verify goods received
;; 4. Complete transaction
(contract-call? .bitcartel complete-transaction-stx u1) ;; for STX
;; OR
(contract-call? .bitcartel complete-transaction-sip010 u1 .token-contract) ;; for SIP-010

;; 5. Rate the seller
(contract-call? .bitcartel rate-user 
    u1                                           ;; escrow ID
    'SP1234567890ABCDEF1234567890ABCDEF12345678  ;; seller address
    u5                                           ;; 5-star rating
)
```

### Dispute Resolution

```clarity
;; Either party can dispute
(contract-call? .bitcartel dispute-transaction u1)

;; Admin resolves (refund to buyer)
(contract-call? .bitcartel resolve-dispute-stx u1 true)
;; OR pay seller
(contract-call? .bitcartel resolve-dispute-stx u1 false)
```

### Admin Functions

```clarity
;; Add new supported token
(contract-call? .bitcartel add-supported-token 
    'SP2C2HDM2JCYNHFZN3V73KMWF8HQJJKQVXZS4TJR5.arkadiko-token 
    "USDA"
)

;; Toggle token status (enable/disable)
(contract-call? .bitcartel toggle-token-status 
    'SP2C2HDM2JCYNHFZN3V73KMWF8HQJJKQVXZS4TJR5.arkadiko-token
)

;; Emergency refund (30+ days old escrows)
(contract-call? .bitcartel emergency-refund-stx u1)
```

## Supported Tokens

The platform supports STX natively and any SIP-010 fungible tokens that have been whitelisted by administrators. Popular tokens that can be added include:

- **USDA** (Arkadiko USD) - `SP2C2HDM2JCYNHFZN3V73KMWF8HQJJKQVXZS4TJR5.arkadiko-token`
- **xBTC** (Wrapped Bitcoin) - `SP3DX3H4FEYZJZ586MFBS25ZW3HZDMEW92260R2PR.Wrapped-Bitcoin`
- **ALEX** Token - `SP3K8BC0PPEVCV7NZ6QSRWPQ2JE9E5B6N3PA0KBR9.alex-token`
- **STX** (Native token - always supported)

## Fee Structure

- **Platform Fee**: 2.5% (250 basis points) on all transactions
- **Fee Calculation**: Automatically calculated and deducted during escrow creation
- **Fee Distribution**: Platform fees go to contract owner
- **Multi-Token Fees**: Fees collected in same token as transaction

## Security Features

### Hash Verification
- **Item Hash**: SHA-256 hash of digital goods for verification
- **Delivery Hash**: SHA-256 hash of delivery proof/access credentials
- **Immutable Records**: All hashes stored on-chain for dispute resolution

### Fund Protection
- **Escrow Security**: Funds locked in contract until completion
- **Emergency Refunds**: Automatic refund for abandoned transactions (30+ days)
- **Dispute Resolution**: Admin mediation for transaction conflicts
- **Multi-Token Safety**: Standardized SIP-010 interface ensures token compatibility

### Access Controls
- **Owner Functions**: Critical admin functions restricted to contract deployer
- **Party Validation**: Only buyer/seller can perform transaction actions
- **Rating Restrictions**: Users cannot rate themselves or rate twice

## Integration Guide

### For Token Projects

1. **SIP-010 Compliance**: Ensure your token implements the standard SIP-010 trait
2. **Contact Admins**: Request token whitelisting through official channels
3. **Provide Details**: Token contract address and display name
4. **Testing**: Thoroughly test integration on Stacks testnet

### For Frontend Developers

1. **Contract Interaction**: Use Stacks.js for contract calls
2. **Event Monitoring**: Monitor contract events for real-time updates
3. **Hash Generation**: Implement client-side hash generation for items/delivery
4. **Multi-Token UI**: Support both STX and SIP-010 token workflows

## Development Roadmap

### Phase 1: Core Infrastructure ✅
- **Basic Escrow System**: STX-based escrow with buyer/seller protection
- **Reputation System**: On-chain ratings and transaction history
- **Dispute Resolution**: Admin-mediated conflict resolution
- **Emergency Refunds**: Automatic refund for abandoned transactions

### Phase 2: Multi-Token Ecosystem ✅
- **Multi-Token Support**: Add support for SIP-010 fungible tokens beyond STX
- **Token Management**: Admin controls for whitelisting and managing supported tokens
- **Cross-Token Fees**: Platform fee collection in multiple token types
- **Token Validation**: Comprehensive SIP-010 compliance checking

### Phase 3: Advanced Marketplace Features (In Progress)
- **Frontend Interface**: Complete web-based marketplace UI
- **Escrow Templates**: Pre-configured escrow types for common digital goods categories
- **Bulk Operations**: Allow sellers to create multiple escrows simultaneously
- **Advanced Search**: On-chain indexing and filtering for marketplace discovery

### Phase 4: Intelligent Automation (Q2 2025)
- **Automated Dispute Resolution**: AI-powered dispute resolution using on-chain evidence
- **Smart Categorization**: Automatic classification of digital goods
- **Predictive Analytics**: Transaction success probability and risk assessment
- **Dynamic Pricing**: Market-driven fee adjustment mechanisms

### Phase 5: Subscription & Recurring Payments (Q3 2025)
- **Subscription Model**: Recurring payment support for subscription-based digital services
- **Payment Scheduling**: Automated recurring escrow creation
- **Subscription Management**: Cancel, pause, and modify recurring payments
- **Revenue Streaming**: Continuous payment flows for ongoing services

### Phase 6: NFT & Digital Asset Integration (Q4 2025)
- **NFT Integration**: Support for NFT-based digital goods and collectibles
- **Digital Rights Management**: On-chain licensing and usage rights
- **Asset Verification**: Authenticity checking for digital assets
- **Royalty Distribution**: Automated creator royalty payments

### Phase 7: Enhanced Reputation & Staking (Q1 2026)
- **Reputation Staking**: Allow users to stake STX to boost their reputation scores
- **Reputation Mining**: Earn tokens for positive marketplace participation
- **Trust Networks**: Community-driven reputation validation
- **Reputation Insurance**: Stake-backed guarantees for high-value transactions

### Phase 8: Cross-Chain & Bitcoin Integration (Q2 2026)
- **Cross-Chain Bridge**: Enable Bitcoin-native payments through Stacks bridge
- **Lightning Network**: Instant Bitcoin payments for digital goods
- **Multi-Chain Assets**: Support for assets from other blockchains
- **Atomic Swaps**: Direct cross-chain asset exchanges

### Phase 9: Decentralized Governance (Q3 2026)
- **Governance Token**: Introduce marketplace governance token for community decision-making
- **DAO Structure**: Decentralized autonomous organization for platform governance
- **Community Proposals**: On-chain voting for platform improvements
- **Treasury Management**: Community-controlled platform treasury

### Phase 10: Enterprise & API Platform (Q4 2026)
- **Enterprise APIs**: RESTful APIs for business integrations
- **White-label Solutions**: Customizable marketplace for enterprises
- **Analytics Dashboard**: Comprehensive marketplace analytics
- **Mobile Applications**: Native iOS and Android apps

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write comprehensive tests for new features
4. Ensure all tests pass (`clarinet test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request with detailed description

## Security Considerations

- All user inputs are validated and sanitized
- Proper error handling prevents contract exploitation
- Funds are secured through battle-tested escrow patterns
- Multi-token support uses standardized SIP-010 interface
- Token transfers include comprehensive error handling
- Hash verification prevents fraud and disputes
- Emergency mechanisms protect against abandoned transactions
- Regular security audits recommended for production deployment

## Support

For support, please:
- Open an issue on GitHub for bugs and feature requests
- Join our Discord community for development discussions
- Contact the development team for partnership inquiries
- Review the documentation for implementation guidance

## Acknowledgments

- Stacks Foundation for blockchain infrastructure
- Clarity language documentation and community
- SIP-010 standard contributors
- Open source contributors and testers