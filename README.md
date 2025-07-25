
## 🌾 **HarvestShare Smart Contract Overview**

### 🎯 Purpose

* **Empowers farmers** to hedge against low crop yields through community-funded microinsurance.
* **Enables supporters/investors** to back agricultural productivity and earn returns.
* **Uses an oracle** for yield verification, allowing tamper-proof data integration.
* **Promotes sustainable agriculture**, disaster resilience, and transparent funding.

---

## 🛠 Core Components

### 👨‍🌾 Farmer Lifecycle

* `register-farmer`: Onboards verified farmers.
* Farmers have a **reputation score** that influences insurance premiums.
* A farmer's performance across seasons is tracked to build trust and reputation.

### 🌱 Insurance Season Lifecycle

* `create-season`: Farmer starts a crop season and defines expected yield, coverage, and duration.
* `support-season`: Community members contribute to the season pool with 20% return potential.
* `report-yield`: Oracle sets actual yield, triggering reward or compensation logic.
* `process-claim`: Handles payouts or reward distribution.
* `withdraw-support`: Supporters claim their returns post-harvest.

### 📊 Tracking & Auditing

* `crop-yield-history`: Averages, best/worst yields across seasons.
* `community-pools`: Aggregated stats per crop type.
* `get-platform-stats`: Total farmers, seasons, coverage, etc.

---

## 🔐 Security & Economic Design

| Security Measure           | Implementation                           |
| -------------------------- | ---------------------------------------- |
| Oracle-restricted updates  | `set-oracle`, `report-yield` permissions |
| Double-claim protection    | `claim-paid`, `paid-out` flags           |
| Yield manipulation guard   | Oracle-only yield reporting              |
| Reputation dynamics        | Adjusted after good harvests (no claim)  |
| Fee collection             | 3% platform fee sent to contract-owner   |
| Pool over-contribution cap | Max 2x coverage cap enforced             |

---

## 🧠 Smart Design Features

### ✅ Reputation-Based Premiums

```clojure
calculate-premium: base-rate - discount(reputation)
```

### 📉 Yield-Based Claims

```clojure
calculate-payout: triggered if yield < threshold (default: 70%)
```

### 🧾 Supporter ROI Logic

* 20% promised return if harvest is successful.
* Pro-rata return or full pool refund if a claim is made.

### 🧑‍🌾 Oracle Flexibility

* Only the contract owner can appoint or change the oracle.

---

## 📈 Example Workflow

1. **Registration**

   * Farmer registers via `register-farmer`.
2. **Insurance Setup**

   * Farmer creates season via `create-season`.
   * Community funds it via `support-season`.
3. **Season End**

   * Oracle submits yield via `report-yield`.
4. **Claim or Rewards**

   * Farmer calls `process-claim`.
   * Supporters call `withdraw-support`.
