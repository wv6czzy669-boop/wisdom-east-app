# EAST. ARCHITECTURE v1.0

**Status:** Foundational Architecture
**Purpose:** Long-term technical and product north star
**Architecture horizon:** 5+ years
**Primary principle:** The ritual remains simple even when the system behind it becomes powerful.

---

# 1. Executive Decision

EAST. should begin as a **modular monolith**, not as a microservices system.

The platform will initially consist of:

* One PostgreSQL database in Supabase
* Supabase Auth
* Supabase Storage
* A controlled server-side API layer
* Supabase Edge Functions for provider integrations and asynchronous operations
* Next.js website deployed to Vercel
* Flutter mobile application
* Dodo Payments for eligible web and physical-commerce payments
* Printify as the first fulfilment provider
* Apple StoreKit for digital features unlocked inside the iOS application
* GitHub as the source of truth for all application and infrastructure code

The system will be divided into clearly bounded domains, but these domains will initially live inside one backend and one database.

This provides:

* clean separation without operational complexity;
* easier testing and deployment;
* fewer failure points;
* lower maintenance;
* a clear future path to extract services only when actual scale requires it.

**EAST. should not start with microservices.**

Microservices would currently create more deployment, monitoring, authentication, transaction and consistency problems than they solve.

---

# 2. The Most Important Architectural Rule

## Supabase is EAST.’s operational source of truth

Printify is not the product database.

Dodo Payments is not the order database.

Apple is not the entitlement database.

Vercel is not the backend.

Flutter is not the ritual database.

The authoritative EAST. state lives in PostgreSQL.

External providers are treated as integrations.

Their identifiers and states are synchronized into EAST., but their internal data models must never become EAST.’s core domain model.

This prevents the platform from becoming permanently dependent on:

* Printify;
* Dodo Payments;
* Apple;
* a particular fulfilment company;
* a particular payment company;
* a particular frontend framework.

Supabase provides a full PostgreSQL database, Auth integration, Storage and APIs; its security model can combine Auth identities with PostgreSQL Row Level Security.

---

# 3. Architectural Shape

```text
                         EAST. PLATFORM

          ┌──────────────────────────────────────────┐
          │              User Interfaces             │
          │                                          │
          │  Flutter App   Next.js Web   Admin Tool  │
          │  Future App    Future Desktop Public API │
          └─────────────────────┬────────────────────┘
                                │
                       EAST. API CONTRACT
                                │
          ┌─────────────────────▼────────────────────┐
          │         Application Service Layer        │
          │                                          │
          │ Ritual  Identity  Content  Commerce      │
          │ Orders  Fulfilment  Notifications        │
          │ Analytics  Automation  Administration    │
          └─────────────────────┬────────────────────┘
                                │
          ┌─────────────────────▼────────────────────┐
          │          PostgreSQL / Supabase           │
          │                                          │
          │ Operational data  RLS  Events  Jobs      │
          │ Audit records  Read models  Storage refs │
          └─────────────────────┬────────────────────┘
                                │
             ┌──────────────────┼───────────────────┐
             │                  │                   │
          Printify        Dodo Payments      Apple StoreKit
          Fulfilment       Web payments      App entitlements
```

---

# 4. Bounded Domains

The backend must be organized by business domain, not by technical file type.

## 4.1 Identity

Responsible for:

* users;
* profiles;
* authentication;
* roles;
* consent;
* account deletion;
* localization preferences;
* communication preferences.

It must not contain ritual, product or order logic.

## 4.2 Ritual

Responsible for:

* daily ritual eligibility;
* ritual completion;
* revealed wisdom;
* 24-hour silence;
* reflection saving;
* kept reflections;
* ritual history.

This is the sacred product core.

Commerce must never directly mutate the ritual state.

## 4.3 Content

Responsible for:

* wisdoms;
* essays;
* journal prompts;
* collections of philosophical content;
* publication state;
* localization;
* editorial sequencing.

## 4.4 Catalog

Responsible for:

* EAST. Objects;
* product descriptions;
* product variants;
* collections;
* media;
* prices displayed by EAST.;
* availability;
* publication status.

## 4.5 Commerce

Responsible for:

* carts;
* checkout intent;
* payments;
* customers;
* orders;
* refunds;
* taxes as reported by the payment provider;
* currency;
* order totals.

## 4.6 Fulfilment

Responsible for:

* Printify synchronization;
* manufacturing;
* shipping;
* tracking;
* provider status;
* fulfilment failures;
* future fulfilment providers.

## 4.7 Entitlements

Responsible for:

* Keeper ownership;
* future digital access rights;
* App Store purchases;
* web-based eligible access rights;
* entitlement restoration;
* entitlement source.

Entitlements must be separate from payments.

A payment is an economic event.

An entitlement is a permission.

They are related, but they are not the same entity.

## 4.8 Notifications

Responsible for:

* push notification registrations;
* notification preferences;
* message templates;
* scheduled deliveries;
* delivery attempts;
* provider responses.

## 4.9 Analytics

Responsible for:

* behavioural events;
* commerce funnel events;
* attribution;
* aggregated reporting;
* operational metrics.

## 4.10 Automation

Responsible for:

* inbound webhooks;
* background jobs;
* retries;
* dead-letter processing;
* reconciliation;
* synchronization.

---

# 5. Ritual Architecture

## 5.1 The ritual remains local-first

The existing mobile ritual should not become dependent on a live network connection.

The Flutter app should be capable of:

* opening;
* determining whether today’s ritual is available;
* running every transition;
* revealing the already-selected wisdom;
* entering the 24-hour silence;
* saving the result locally;

without a network request during the visible ritual.

This preserves:

* timing;
* emotional continuity;
* offline resilience;
* performance;
* protection from backend latency.

## 5.2 Server synchronization occurs outside the ritual

Synchronization should happen:

* on app launch before the ritual starts;
* after the ritual has completed;
* when the app returns to a neutral screen;
* during background-safe moments;
* when a user signs in or changes devices.

It must not happen between:

* Pause;
* Feel;
* Ask From Your Heart;
* Reveal;
* Reflection.

## 5.3 Ritual authority

For anonymous users:

* the device maintains local ritual state;
* a generated anonymous installation ID identifies the installation;
* ritual data may later be attached to an account.

For signed-in users:

* the server becomes the cross-device authority;
* the device maintains an offline cache;
* conflicts are resolved using server timestamps and immutable ritual records.

## 5.4 Time enforcement

Never use only the device clock to determine ritual availability.

A user can change the device time.

The architecture should use:

* trusted server time when available;
* last known server-time offset;
* monotonic elapsed time locally where practical;
* server reconciliation after reconnection.

However, the system should not become aggressively punitive.

The purpose is to preserve the ritual, not to build an anti-cheat system.

## 5.5 Ritual records should be append-oriented

A completed ritual should become an immutable historical record.

It should not be repeatedly overwritten.

A ritual completion record contains:

* user or installation identifier;
* wisdom identifier;
* revealed timestamp;
* next eligibility timestamp;
* timezone context;
* app version;
* content version;
* source device;
* synchronization state.

The current ritual eligibility can be derived or cached separately.

---

# 6. Identity and Authentication

## 6.1 Accounts should remain optional initially

EAST. must not require account creation before the first ritual.

Mandatory registration would damage the experience.

Recommended sequence:

1. User installs EAST.
2. User experiences the ritual without an account.
3. The device receives an installation identity.
4. The user may later create an account to preserve reflections, orders and access across devices.
5. Anonymous local history is safely linked to that account.

## 6.2 Authentication methods

Initial support:

* Sign in with Apple;
* email magic link or one-time password.

Avoid passwords unless there is a strong product reason.

Do not add Google login solely because it is common.

## 6.3 Application roles

Use a minimal role system:

* `user`
* `editor`
* `operator`
* `admin`

Do not create dozens of roles.

Use explicit permissions internally if administration grows.

## 6.4 Profile separation

Supabase Auth should own authentication identity.

An EAST. `profiles` record should own product-specific information.

Do not place business data inside authentication metadata.

---

# 7. Database Design Principles

## 7.1 Universal conventions

Every primary business table should generally contain:

* UUID primary key;
* `created_at`;
* `updated_at` where mutation is allowed;
* explicit lifecycle state;
* external identifiers only where relevant;
* no provider-specific fields mixed into core domain fields.

## 7.2 Use enums carefully

Database enums are appropriate for highly stable values such as:

* order lifecycle;
* publication state;
* payment status.

Avoid enums for values likely to expand frequently, such as:

* product categories;
* philosophical traditions;
* tags;
* notification types.

Those should use tables or validated text values.

## 7.3 Money

Never store money as floating-point values.

Store:

* integer minor units;
* ISO currency code.

Example conceptually:

* amount: `7500`
* currency: `USD`

meaning USD 75.00.

## 7.4 Historical snapshots

Orders must preserve historical truth.

When a customer places an order, the system must snapshot:

* product name;
* variant name;
* SKU;
* unit price;
* currency;
* selected options;
* product image reference;
* shipping address;
* tax;
* discount.

An old order must not change because a product description or price changes later.

## 7.5 Soft deletion

Do not use soft deletion everywhere.

Use it only where restoration, legal history or references require it.

For published content and products, use lifecycle fields such as:

* draft;
* scheduled;
* active;
* archived.

For analytics events and financial records, use immutable retention rather than deletion.

---

# 8. Core Database Tables

The following is the recommended v1 schema boundary.

## 8.1 Identity

### `profiles`

One record per authenticated user.

Core fields:

* `id` referencing Supabase Auth user ID;
* display name;
* locale;
* timezone;
* country code;
* onboarding state;
* account status;
* created timestamp.

Do not place addresses, purchases or favourites directly here.

### `installations`

Represents an application or browser installation.

Core fields:

* installation ID;
* optional user ID;
* platform;
* app version;
* device locale;
* timezone;
* last seen timestamp;
* notification capability;
* installation state.

Do not store invasive device fingerprinting data.

### `user_consents`

Stores versioned consent records.

Core fields:

* user or installation ID;
* consent type;
* policy version;
* granted or denied;
* recorded timestamp;
* region.

---

## 8.2 Ritual and Reflections

### `wisdoms`

The canonical wisdom content.

Core fields:

* stable ID;
* canonical text;
* author or attribution where applicable;
* origin type;
* publication state;
* content version;
* language;
* editorial metadata;
* active date range if scheduled.

A wisdom must never be identified only by its text.

### `wisdom_translations`

Needed only once multiple languages are introduced.

Core fields:

* wisdom ID;
* locale;
* translated text;
* translation status;
* translator or source;
* version.

Do not create separate wisdom tables per language.

### `ritual_completions`

Immutable record of completed rituals.

Core fields:

* user ID or installation ID;
* wisdom ID;
* revealed timestamp;
* next eligible timestamp;
* timezone;
* content version;
* client-generated idempotency key;
* synchronization metadata.

A uniqueness strategy must prevent the same completion being submitted multiple times.

### `ritual_access_state`

A compact current-state projection.

Core fields:

* user or installation ID;
* last completion ID;
* next eligible timestamp;
* current wisdom ID if necessary;
* version number.

This exists for fast reads.

It must not replace the immutable completion history.

### `reflections`

User-generated reflection associated with a ritual.

Core fields:

* user ID;
* ritual completion ID;
* encrypted or protected reflection text;
* created timestamp;
* modified timestamp;
* deletion timestamp where required;
* synchronization version.

### `kept_reflections`

Represents whether a reflection has been deliberately kept.

Core fields:

* user ID;
* reflection ID;
* kept timestamp.

This can alternatively be a field on `reflections`, but a separate relation is better if “kept” later gains metadata, ordering or collections.

### `user_wisdom_favorites`

For wisdoms saved independently from a written reflection.

Core fields:

* user ID;
* wisdom ID;
* created timestamp.

Use a unique constraint on user plus wisdom.

---

## 8.3 Editorial Content

### `content_entries`

A unified editorial content model for:

* essays;
* journal introductions;
* announcements;
* philosophical notes;
* editorial pages.

Core fields:

* type;
* slug;
* title;
* excerpt;
* content document;
* author;
* publication state;
* published timestamp;
* locale;
* SEO metadata;
* content version.

Use structured rich-text JSON or Markdown with strict rendering rules.

Do not store arbitrary executable HTML.

### `content_collections`

Editorial groupings such as:

* On Silence;
* The Practice of Attention;
* Objects for Stillness.

### `content_collection_items`

Ordered relationship between entries and collections.

---

## 8.4 Catalog and Objects

### `products`

The canonical EAST. Object.

Core fields:

* stable product ID;
* slug;
* title;
* subtitle;
* editorial description;
* product type;
* publication state;
* primary collection;
* brand state;
* tax category;
* fulfilment mode;
* active timestamp;
* archive timestamp.

A product is not a Printify product.

It is an EAST. domain object.

### `product_variants`

Core fields:

* product ID;
* SKU;
* option values;
* EAST. price;
* currency;
* compare-at price where genuinely needed;
* weight and dimensions if required;
* active state;
* inventory policy;
* fulfilment reference.

### `product_options`

Examples:

* size;
* format;
* material;
* frame;
* colour.

### `product_option_values`

The allowed values within an option.

Avoid storing variant information only in free-form JSON.

### `product_media`

Core fields:

* product ID;
* storage asset ID;
* media type;
* alt text;
* display order;
* role such as hero, detail, lifestyle or scale;
* focal point metadata.

### `product_collections`

Commerce/editorial collections.

### `product_collection_items`

Ordered product membership.

### `product_provider_mappings`

Links EAST. variants to provider variants.

Core fields:

* EAST. product ID;
* EAST. variant ID;
* provider;
* provider shop ID;
* provider product ID;
* provider variant ID;
* provider blueprint ID;
* provider print-provider ID;
* synchronization status;
* last synchronized timestamp.

This isolation makes replacing Printify possible later.

### `product_sync_versions`

Stores the result of each synchronization.

Core fields:

* provider mapping;
* source payload hash;
* resulting catalog version;
* status;
* error;
* timestamp.

---

## 8.5 Cart and Checkout

### `carts`

Core fields:

* optional user ID;
* installation or anonymous session ID;
* currency;
* state;
* expiration;
* last activity timestamp.

### `cart_items`

Core fields:

* cart ID;
* product variant ID;
* quantity;
* price snapshot;
* added timestamp.

The backend must revalidate price and availability before checkout.

### `checkout_sessions`

Represents EAST.’s checkout process, independently of the payment provider.

Core fields:

* user or guest identity;
* cart ID;
* provider;
* provider checkout ID;
* status;
* currency;
* totals;
* customer email;
* expiration;
* idempotency key.

Dodo currently exposes checkout sessions and payment webhooks. These should be used as provider mechanisms, while EAST. retains its own checkout and order state.

---

## 8.6 Orders

### `orders`

The authoritative order record.

Core fields:

* public order number;
* optional user ID;
* customer email;
* order status;
* payment status;
* fulfilment status;
* currency;
* subtotal;
* discount;
* shipping;
* tax;
* total;
* payment provider;
* checkout session ID;
* placed timestamp;
* cancelled timestamp.

Do not expose the UUID as the customer-facing order number.

### `order_items`

Contains immutable product snapshots.

### `order_addresses`

Contains snapshot addresses for:

* shipping;
* billing.

Do not point completed orders only to mutable address-book records.

### `customer_addresses`

Optional reusable address book for signed-in users.

### `payments`

Core fields:

* order ID;
* provider;
* provider payment ID;
* amount;
* currency;
* status;
* authorized timestamp;
* captured timestamp;
* refunded amount;
* provider response reference.

### `refunds`

Separate records for partial and full refunds.

### `order_status_history`

Append-only state changes.

Core fields:

* order ID;
* previous status;
* new status;
* source;
* timestamp;
* human or automated actor;
* reason.

---

## 8.7 Fulfilment

### `fulfilments`

One order may have multiple fulfilments.

Core fields:

* order ID;
* provider;
* provider order ID;
* status;
* submitted timestamp;
* production timestamp;
* shipped timestamp;
* delivered timestamp;
* failed timestamp.

### `fulfilment_items`

Maps order items to fulfilments.

### `shipments`

Core fields:

* fulfilment ID;
* carrier;
* tracking number;
* tracking URL;
* shipping status;
* shipped and delivered timestamps.

### `fulfilment_events`

Append-only normalized provider events.

Printify supports product management, order submission and webhook notifications. EAST. should normalize these events rather than allowing raw Printify states to flow directly into the user interfaces.

---

## 8.8 Entitlements

### `entitlements`

Core fields:

* user ID;
* entitlement type;
* status;
* source;
* source transaction ID;
* acquired timestamp;
* expires timestamp where applicable;
* revoked timestamp;
* environment;
* verification timestamp.

Examples:

* `keeper_lifetime`;
* future subscription entitlement;
* future content collection access.

### `store_transactions`

Raw but controlled references to:

* Apple transactions;
* future Google Play transactions;
* eligible web transactions.

Never trust a client claim that a purchase succeeded.

The backend or verified platform mechanism must validate entitlement ownership.

For iOS, digital functionality or content unlocked inside the app generally must use Apple In-App Purchase. Physical goods consumed outside the application should use non-IAP payment methods. Therefore Dodo and StoreKit must remain separate commerce channels.

---

## 8.9 Notifications

### `notification_preferences`

Core fields:

* user or installation ID;
* category;
* channel;
* enabled;
* quiet hours;
* timezone.

### `push_tokens`

Core fields:

* installation ID;
* platform;
* token;
* token state;
* last verified timestamp.

### `notification_templates`

Versioned templates by:

* notification type;
* locale;
* channel.

### `notification_jobs`

Represents intended delivery.

### `notification_deliveries`

Stores each send attempt and provider result.

Never treat “request accepted by provider” as “notification delivered.”

---

## 8.10 Integrations and Automation

### `webhook_events`

Every external webhook enters here first.

Core fields:

* provider;
* provider event ID;
* event type;
* signature verification result;
* received timestamp;
* payload;
* processing status;
* attempt count;
* processed timestamp;
* error summary.

A unique constraint on provider plus external event ID prevents duplicate processing.

### `outbox_events`

Records internal events that must be processed asynchronously.

Examples:

* order placed;
* payment confirmed;
* fulfilment requested;
* product published;
* reflection synchronized.

### `background_jobs`

Core fields:

* job type;
* payload reference;
* state;
* scheduled timestamp;
* attempts;
* locked timestamp;
* completed timestamp;
* error.

### `dead_letter_jobs`

Jobs moved here after exhausting retries.

### `integration_connections`

Stores non-secret integration metadata:

* provider;
* environment;
* account identifier;
* connection state;
* last successful synchronization.

Secrets remain in server-managed environment variables or secret storage.

Supabase supports asynchronous database webhooks, scheduled functions through `pg_cron` and managed PostgreSQL queues through `pgmq`; these are suitable for a measured job-processing layer without introducing a separate message broker immediately.

---

## 8.11 Analytics

### `analytics_events`

Append-oriented event stream.

Core fields:

* event ID;
* event name;
* anonymous ID;
* optional user ID;
* session ID;
* platform;
* occurred timestamp;
* received timestamp;
* properties;
* product ID where relevant;
* order ID where relevant;
* locale;
* country;
* app or site version;
* consent context.

### `analytics_sessions`

Optional derived session representation.

### Aggregated views or materialized views

Examples:

* daily product views;
* daily checkout starts;
* daily purchases;
* product conversion;
* country sales;
* ritual retention;
* notification effectiveness.

Do not start by creating dozens of reporting tables.

Start with:

* one clean event contract;
* a small number of operational aggregates;
* materialized views for expensive reports.

When analytics volume becomes significant, replicate analytics data into a dedicated warehouse rather than overloading the transactional database. Supabase documents replication and change-data-capture as a path for analytics and operational reporting.

---

# 9. API Architecture

## 9.1 Do not let every client directly query every table

Supabase can safely expose data through its API when RLS is correctly configured, but EAST. should use a hybrid model.

Direct client access is appropriate for narrowly scoped user-owned data such as:

* reading the current user profile;
* reading the user’s kept reflections;
* updating notification preferences;
* reading public published content.

Server-owned endpoints are required for:

* ritual completion reconciliation;
* checkout creation;
* order creation;
* payment processing;
* webhook processing;
* Printify interaction;
* entitlement verification;
* administrative publication;
* analytics aggregation;
* anything using provider secrets;
* multi-table transactional operations.

RLS remains mandatory even when the service layer exists. Supabase explicitly recommends RLS and least-privilege policies for frontend-accessible data.

## 9.2 API versioning

Use a stable versioned namespace from the beginning:

```text
/api/v1/...
```

Version the public contract, not every internal function.

Breaking contract changes require:

```text
/api/v2/...
```

Non-breaking field additions may remain in v1.

## 9.3 Resource groups

Recommended API families:

```text
/api/v1/identity
/api/v1/ritual
/api/v1/reflections
/api/v1/content
/api/v1/catalog
/api/v1/cart
/api/v1/checkout
/api/v1/orders
/api/v1/entitlements
/api/v1/notifications
/api/v1/analytics
/api/v1/admin
/api/v1/webhooks
```

## 9.4 API contract standards

Every endpoint should have:

* authenticated or explicitly anonymous identity;
* request validation;
* typed response schema;
* stable error code;
* correlation ID;
* rate-limit policy;
* idempotency support for mutations;
* documented authorization rules.

## 9.5 Idempotency

Mandatory for:

* ritual synchronization;
* checkout creation;
* order creation;
* payment event handling;
* fulfilment submission;
* refunds;
* product publication;
* webhook processing.

Network retries must not create:

* duplicate orders;
* duplicate payments;
* duplicate Printify fulfilments;
* duplicate ritual records.

## 9.6 Next.js role

Next.js should have three roles:

1. Render the public editorial website.
2. Provide server-side website-specific orchestration.
3. Act as one caller of the EAST. backend.

It should not become the only backend for the entire platform.

Flutter and future clients must not depend on undocumented Next.js internals.

Next.js Server Actions are suitable for website form mutations, but long-lived platform contracts should remain in an explicit API/service layer rather than being available only as component-bound actions.

---

# 10. Product Automation Pipeline

The proposed ideal flow:

```text
Upload design
→ Printify creates product
→ Backend syncs
→ Supabase updates
→ Website updates
→ App updates
```

is directionally correct but currently hides several required decisions.

A design file alone does not determine:

* product blueprint;
* print provider;
* print area;
* placement;
* available colours;
* available sizes;
* mockup rules;
* pricing;
* margin;
* title;
* editorial description;
* shipping regions;
* quality acceptance.

Therefore the correct future workflow is:

```text
Upload approved design
        ↓
Choose or infer EAST. Product Template
        ↓
Validate dimensions, DPI and print area
        ↓
Create Printify draft product
        ↓
Retrieve variants and production cost
        ↓
Calculate EAST. prices using pricing policy
        ↓
Generate or retrieve mockups
        ↓
Create EAST. catalog draft
        ↓
Run automated validation
        ↓
Single human publication approval
        ↓
Publish to Printify and EAST.
        ↓
Invalidate website cache
        ↓
Mobile and website receive updated catalog
```

## 10.1 Product templates

Create reusable internal templates such as:

* Journal — Hardcover;
* Print — Framed;
* Print — Unframed;
* Ritual Card Set;
* Textile Object.

Each template defines:

* Printify blueprint;
* approved print provider;
* approved variants;
* design placement;
* minimum resolution;
* margin formula;
* supported shipping regions;
* default copy structure;
* mockup selection;
* quality rules.

This allows “upload a design” to become genuinely close to automation.

## 10.2 Human approval is intentional

Zero manual operations is not always good architecture.

For a premium brand, accidental publication is more damaging than one approval step.

The goal should be:

**one deliberate editorial approval, zero repetitive data entry.**

## 10.3 Catalog publication event

When a product becomes active:

1. Product transaction commits.
2. `product.published` is added to the outbox.
3. Website cache is invalidated.
4. Search/read models update.
5. App catalog version changes.
6. Analytics receives a catalog publication event.
7. Failures retry independently.

The product publication itself must not fail because a secondary analytics or cache operation failed.

---

# 11. Order and Payment Flow

## 11.1 Website purchase flow

```text
User opens product
→ Adds variant to cart
→ Backend validates product and price
→ EAST. creates checkout session
→ Dodo checkout is created
→ User pays
→ Dodo sends signed webhook
→ Webhook is stored and verified
→ Payment is normalized
→ EAST. order becomes paid
→ Fulfilment job is queued
→ Printify order is submitted
→ Printify status webhooks update fulfilment
→ User sees tracking in website/app
```

## 11.2 The browser redirect is not proof of payment

Never mark an order paid merely because the user reached a success page.

The verified payment webhook is authoritative.

Dodo provides webhook events for transaction, refund and dispute lifecycle changes and uses webhook secrets/signing mechanisms.

## 11.3 Order creation timing

Recommended approach:

* create a pending order or checkout record before redirect;
* create/finalize the authoritative order after verified payment;
* preserve enough checkout snapshot data to recover abandoned or delayed webhooks.

## 11.4 Fulfilment submission

Printify submission occurs only after:

* payment is verified;
* address passes validation rules;
* product-provider mapping exists;
* variant is active;
* order has not previously been submitted.

## 11.5 Reconciliation

Scheduled reconciliation jobs must periodically compare:

* paid checkouts without orders;
* paid orders without fulfilments;
* Printify orders with stale statuses;
* refunds not reflected in EAST.;
* provider events that failed processing.

Webhooks reduce latency.

Reconciliation provides correctness.

Both are required.

---

# 12. Mobile Commerce Boundary

Physical Objects may be discovered and purchased through the app, but this must remain visually and technically beside the ritual.

Recommended navigation:

```text
Ritual
Kept
Objects
Settings
```

or an even quieter entry through a separate Objects surface.

Never show:

* product promotions during Pause;
* offers between Feel and Reveal;
* purchase prompts after wisdom reveal;
* countdown-linked sales;
* commerce badges inside the ritual.

## Payment distinction

### Physical Objects

Physical goods consumed outside the app should use an external physical-commerce payment method rather than Apple IAP. Apple’s guidelines explicitly distinguish these purchases from digital in-app functionality.

### Keeper and future digital access

Keeper or any digital functionality unlocked inside EAST. must remain StoreKit-based on iOS unless a specific current App Store entitlement and storefront rule is deliberately adopted.

Do not combine Keeper and physical product payments into one payment implementation.

---

# 13. Storage Architecture

## 13.1 Storage buckets

Recommended logical buckets:

### `public-content`

For:

* published editorial images;
* product media;
* website assets intended for public access.

### `product-source-private`

For:

* original design files;
* print-ready source files;
* high-resolution masters;
* internal mockups.

Private.

### `user-private`

For:

* future user uploads;
* private journal attachments;
* account-specific exports.

Private and RLS-protected.

### `system-exports`

For:

* temporary account exports;
* reporting exports;
* migration packages.

Private, expiring access only.

## 13.2 File records

Do not rely only on raw storage paths.

Use an `assets` table containing:

* asset ID;
* bucket;
* object path;
* MIME type;
* dimensions;
* file size;
* checksum;
* purpose;
* visibility;
* owner;
* processing state;
* created timestamp.

Domain tables reference asset IDs.

## 13.3 Image derivatives

Generate approved derivatives:

* thumbnail;
* product card;
* product detail;
* high-density display;
* social preview.

Do not make every client download original print-resolution files.

Supabase Storage supports access policies integrated with PostgreSQL security.

---

# 14. Security Architecture

## 14.1 Secret boundary

The following must never exist in Flutter, browser JavaScript or public repositories:

* Printify API token;
* Dodo API key;
* Dodo webhook secret;
* Supabase service-role key;
* Apple verification credentials;
* email provider keys;
* push notification provider secrets;
* administrative signing secrets.

The Supabase service-role key bypasses Row Level Security and must never be exposed to a browser.

## 14.2 Client keys

The Supabase publishable/anonymous key may exist in clients only when:

* all exposed tables have RLS enabled;
* policies are tested;
* no privileged procedure is callable;
* Storage policies are also configured;
* privileged fields are not publicly selectable.

## 14.3 Row Level Security policy model

Default posture:

```text
No access unless explicitly allowed.
```

Examples:

* Public users may read only published catalog and editorial content.
* Users may read and modify only their own profiles and preferences.
* Users may read only their own reflections, orders and entitlements.
* Users may not directly insert payments, refunds, fulfilments or entitlements.
* Clients may not directly alter publication state.
* Service operations use narrowly scoped server functions.

## 14.4 Webhook security

Every webhook handler must:

1. read the raw request body;
2. verify provider signature;
3. reject invalid timestamps or signatures;
4. store the event;
5. detect duplicates;
6. return promptly;
7. process asynchronously;
8. record processing result.

## 14.5 Administrative security

Admin access requires:

* authenticated account;
* explicit server-side role verification;
* multi-factor authentication when available;
* audit logging;
* no client-only permission checks;
* restricted service routes;
* rate limiting;
* confirmation for destructive operations.

## 14.6 Personal data minimization

Do not collect information merely because it may be useful later.

Avoid:

* unnecessary birth dates;
* excessive location tracking;
* contact uploads;
* device fingerprinting;
* raw payment card data;
* storing provider payloads indefinitely without review.

## 14.7 Reflection privacy

Personal reflections may be emotionally sensitive.

They should receive stronger treatment than normal favorites:

* user-scoped RLS;
* no analytics content capture;
* no reflection text in logs;
* no reflection text in crash reports;
* no reflection text sent to AI systems without explicit consent;
* optional future application-level encryption if threat model and cross-device requirements justify it.

---

# 15. Analytics Architecture

## 15.0 Current shipped implementation (EAST. Phase 7)

The taxonomy below (§15.2) is the full future/roadmap vision for this section and is **not** what is currently implemented. The actual shipped analytics surface (`lib/services/analytics_event.dart`, `lib/services/analytics_service.dart`) is a closed, privacy-safe, parameter-free allow-list of exactly six events, with no path to construct or emit any other event name:

* `ritual_completed`
* `kept_saved`
* `reflection_saved`
* `keeper_purchase_started`
* `keeper_purchase_completed`
* `keeper_restore_completed`

No event ever carries parameters — no wisdom/reflection text, no Kept content, no `revealId`/local/CloudKit record identifier, no account fingerprint, and no daily-access timestamp is ever attached to an event, because none of those values are ever passed to one. The current release transport (`DebugLogAnalyticsTransport`) is intentionally local-only/debug-only: it writes the event name to the debug console via `dart:developer` and makes no network call of any kind in any build configuration — there is no production analytics backend wired up today. A real, privacy-reviewed backend could be added later behind the same `AnalyticsTransport` interface without any call site changing, but that is future work, not the current implementation.

The commerce/product/editorial taxonomy in §15.2 describes a future platform this app does not yet have (no product catalog, checkout, or editorial content ships today) and should be read as roadmap, not current state.

## 15.1 Event philosophy

Analytics should answer decisions, not merely collect activity.

Every event must have:

* clear owner;
* clear business question;
* privacy justification;
* stable schema;
* retention policy.

## 15.2 Initial event taxonomy

### Product discovery

* `product_impression`
* `product_viewed`
* `product_media_viewed`
* `collection_viewed`

### Commerce

* `cart_item_added`
* `cart_item_removed`
* `checkout_started`
* `checkout_redirected`
* `payment_completed`
* `payment_failed`
* `order_placed`
* `order_refunded`

### Ritual

* `ritual_available`
* `ritual_started`
* `ritual_completed`
* `reflection_kept`

Do not track individual animation steps unless a real product question requires it.

### Editorial

* `essay_viewed`
* `journal_entry_opened`
* `content_completed`

## 15.3 Required metrics

### Most viewed products

Unique and total `product_viewed` events grouped by product.

### Most sold products

Paid order item quantity and revenue grouped by product and variant.

### Product conversion

```text
Purchasing sessions / product-view sessions
```

Define this precisely and do not change the formula silently.

### Checkout abandonment

```text
Checkout sessions not followed by verified payment
within the defined attribution window
```

### Country distribution

Use:

* order shipping country for physical sales;
* consented coarse analytics geography for browsing;
* App Store reports for digital transactions where relevant.

### Ritual retention

Examples:

* D1;
* D7;
* D30;
* weekly ritual completion rate.

## 15.4 Analytics privacy

Never place the following in analytics event properties:

* reflection text;
* full address;
* email;
* payment payload;
* push token;
* raw IP address beyond necessary short-lived infrastructure processing.

---

# 16. Notifications

## 16.1 Notifications must serve the ritual

They should never become engagement spam.

Initial categories:

* ritual availability;
* order status;
* shipping update;
* account/security;
* rare editorial announcement.

## 16.2 Notification source

The backend determines notification intent.

The client does not independently invent campaign notifications.

## 16.3 Ritual notification scheduling

The system should account for:

* the user’s next eligible time;
* timezone;
* quiet hours;
* notification permission;
* last device token;
* user preference;
* duplicate prevention.

A notification should not be sent merely because a global clock reached midnight.

## 16.4 Delivery design

```text
Notification intent created
→ queued
→ eligibility checked
→ provider request sent
→ delivery attempt recorded
→ retry or failure state
```

Supabase documents a pattern where database events invoke an Edge Function to send push notifications; EAST. may use the same architectural mechanism while retaining its own delivery records and retry controls.

---

# 17. Admin Architecture

## 17.1 Do not build a large dashboard now

Initial administration should use:

* Supabase Dashboard for technical inspection;
* Printify Dashboard for provider-specific production issues;
* Dodo Dashboard for payment-provider investigation;
* a minimal protected EAST. Admin interface for brand-specific operations.

## 17.2 Minimal EAST. Admin responsibilities

Only include actions that cannot safely remain in provider dashboards:

* preview and publish products;
* reorder product and content collections;
* publish essays;
* review failed synchronization jobs;
* retry recoverable jobs;
* inspect order timeline;
* issue controlled refunds when supported;
* manage notification templates;
* inspect system health;
* view audit history.

## 17.3 No direct database editing as normal operations

The Supabase table editor is acceptable during development.

It must not become the long-term operational workflow for:

* product publication;
* refunding;
* order status changes;
* entitlement grants;
* content publication.

Those actions require validation and audit records.

---

# 18. Frontend Architecture

## 18.1 Shared design system, not shared UI code

Flutter and Next.js should not attempt to share components.

They should share:

* design tokens;
* typography definitions;
* spacing scale;
* colour system;
* motion principles;
* editorial tone;
* API schemas;
* product states;
* analytics event definitions.

Each platform should implement native components appropriate to its environment.

## 18.2 Flutter application layers

Conceptual boundaries:

```text
Presentation
Application
Domain
Infrastructure
```

### Presentation

Screens, animations and interaction.

### Application

Use cases such as:

* begin ritual;
* complete ritual;
* keep reflection;
* load Objects;
* restore Keeper.

### Domain

Platform-independent business rules:

* ritual eligibility;
* entitlement behavior;
* catalog entities;
* order states.

### Infrastructure

* local storage;
* Supabase;
* StoreKit;
* networking;
* notifications;
* analytics.

The ritual animation implementation must remain isolated from backend networking.

## 18.3 Next.js website layers

```text
App Router presentation
Server-side page composition
Application services
API client
Content and catalog read models
```

The website should default to server-rendered pages for editorial and product discovery.

Client JavaScript should be added only where interaction requires it.

## 18.4 Website information architecture

Recommended top-level structure:

```text
Home
Ritual
Objects
Journal
Essays
About
```

Commerce functions such as cart and account should remain visually secondary.

## 18.5 Catalog delivery without app updates

The app must receive catalog and editorial content from the backend.

No product should require:

* hard-coded title;
* hard-coded price;
* hard-coded image;
* hard-coded collection;
* App Store release.

However, remotely delivered content must not remotely introduce arbitrary executable UI.

Use a controlled component vocabulary, not remote code.

---

# 19. Content Delivery Model

Remote content should be structured rather than unrestricted.

For example, editorial pages may use approved block types:

* paragraph;
* heading;
* image;
* quotation;
* spacer;
* product reference;
* essay reference;
* ritual invitation.

The client knows how to render these approved blocks.

The backend determines their content and order.

This provides flexibility without turning the app into an unsafe remote webpage renderer.

---

# 20. Performance Architecture

## 20.1 Website

Priorities:

* server rendering;
* static generation for stable editorial pages;
* incremental revalidation after publication;
* optimized images;
* minimal third-party scripts;
* limited client-side hydration;
* geographic CDN delivery;
* database queries through prepared read models.

## 20.2 Mobile

Priorities:

* local ritual assets;
* cached catalog;
* paginated Objects;
* pre-sized images;
* background synchronization;
* no network dependency in core transitions;
* lightweight startup;
* no analytics blocking UI.

## 20.3 Database

Priorities:

* indexes based on real query patterns;
* cursor pagination rather than large offsets;
* materialized views for heavy analytics;
* connection pooling;
* query monitoring;
* avoiding unbounded JSON queries;
* archiving or partitioning analytics when volume requires it.

## 20.4 Cache invalidation

Publication events should explicitly invalidate:

* product pages;
* collection pages;
* home editorial modules;
* app catalog version.

Do not rely only on arbitrary time-based cache expiry.

---

# 21. Reliability and Failure Handling

## 21.1 External providers will fail

The architecture must assume:

* Dodo webhooks may arrive late or more than once;
* Printify may time out;
* provider APIs may rate-limit requests;
* Vercel deployment may succeed while cache invalidation fails;
* push tokens may expire;
* users may close checkout early;
* network requests may be retried.

## 21.2 Retry policy

Jobs should use:

* bounded exponential backoff;
* maximum attempts;
* retryable versus permanent error classification;
* dead-letter state;
* manual retry only after automated retries fail.

## 21.3 Circuit protection

If Printify is unavailable:

* the site remains browsable;
* paid orders remain safely recorded;
* fulfilment submission queues;
* operations receive an alert;
* the customer does not receive a false “in production” state.

## 21.4 Observability

Every server-side request and job should support:

* correlation ID;
* structured logs;
* duration;
* outcome;
* provider reference;
* environment;
* redacted errors.

Required alerts:

* payment webhook failures;
* paid order without fulfilment;
* repeated Printify failures;
* dead-letter jobs;
* unusual entitlement changes;
* database storage threshold;
* backup failure;
* elevated API error rate.

---

# 22. Environments

Maintain three isolated environments:

## Local

Developer machines and local Supabase where practical.

## Staging

Real hosted environment using:

* test Dodo credentials;
* test Printify shop or controlled test workflow;
* Apple sandbox transactions;
* staging Vercel deployment;
* staging Storage buckets;
* staging database.

## Production

No test data mixed with live data.

Environment separation must include:

* Supabase projects;
* provider credentials;
* webhook endpoints;
* storage;
* analytics;
* domains;
* Apple transaction environment handling.

Do not use a boolean `is_test` column as a substitute for environment isolation.

---

# 23. Repository Strategy

Recommended monorepo:

```text
east-platform/
  apps/
    mobile/
    web/
    admin/
  packages/
    api-contracts/
    design-tokens/
    analytics-contracts/
    content-schema/
  supabase/
    migrations/
    functions/
    seed/
    tests/
  docs/
    architecture/
    decisions/
    runbooks/
```

## Important limitation

Dart and TypeScript cannot directly share runtime model code.

They can share contracts through:

* OpenAPI;
* JSON Schema;
* generated client models;
* common event definitions.

Do not manually maintain the same API models twice.

## Architecture Decision Records

Every major irreversible decision should create an ADR.

Examples:

* ADR-001: Modular monolith;
* ADR-002: Supabase as operational source of truth;
* ADR-003: StoreKit separated from physical commerce;
* ADR-004: Local-first ritual;
* ADR-005: Provider-neutral fulfilment model.

---

# 24. Database Migration Discipline

All schema changes must be migrations committed to Git.

Never make production-only manual schema changes.

Every migration should include:

* forward change;
* data migration plan;
* compatibility assessment;
* rollback or recovery plan;
* RLS changes;
* index impact;
* staging validation.

Use expand-and-contract migrations for breaking changes:

1. Add new structure.
2. Support old and new clients.
3. Backfill data.
4. Move readers and writers.
5. Observe.
6. Remove old structure later.

This matters because mobile users do not all upgrade immediately.

---

# 25. Testing Strategy

## 25.1 Unit tests

For:

* ritual eligibility;
* price calculation;
* order state transitions;
* entitlement resolution;
* retry classification;
* content validation.

## 25.2 Database tests

For:

* RLS;
* constraints;
* uniqueness;
* functions;
* state transition rules;
* migration behavior.

## 25.3 Contract tests

Ensure Flutter, Next.js and backend agree on:

* request fields;
* response fields;
* enum values;
* errors;
* version compatibility.

## 25.4 Integration tests

For:

* Dodo webhook verification;
* payment-to-order transition;
* Printify product synchronization;
* Printify fulfilment submission;
* Apple entitlement verification;
* notification delivery pipeline.

## 25.5 End-to-end tests

Critical paths only:

* complete ritual;
* save reflection;
* restore Keeper;
* browse product;
* purchase physical Object;
* track order;
* publish a product.

## 25.6 Ritual regression protection

The locked ritual requires dedicated golden and timing tests.

Backend or commerce changes must never silently alter:

* transition timing;
* audio sequencing;
* text placement;
* return-to-black behavior;
* 24-hour lock.

---

# 26. Data Ownership Matrix

| Data                         | Authority                         |
| ---------------------------- | --------------------------------- |
| User authentication          | Supabase Auth                     |
| User profile                 | EAST. PostgreSQL                  |
| Ritual history               | EAST. PostgreSQL with local cache |
| Wisdom content               | EAST. PostgreSQL                  |
| Product editorial identity   | EAST. PostgreSQL                  |
| Print specification          | EAST. plus provider mapping       |
| Provider manufacturing state | Printify, normalized into EAST.   |
| Customer-facing order        | EAST. PostgreSQL                  |
| Payment provider transaction | Dodo, normalized into EAST.       |
| Keeper transaction           | Apple where purchased through iOS |
| Keeper entitlement           | EAST. entitlement layer           |
| Product media                | Supabase Storage                  |
| Design master files          | Private Supabase Storage          |
| Analytics events             | EAST. analytics layer             |
| Source code                  | GitHub                            |

---

# 27. Assumptions That Must Be Challenged

## 27.1 “No technical debt”

Literally zero technical debt is impossible.

The correct goal is:

* deliberate trade-offs;
* documented decisions;
* bounded debt;
* no accidental duplication;
* scheduled removal of temporary solutions.

## 27.2 “Everything must use one backend”

One logical platform backend is correct.

One physical component for every future workload may not remain correct.

Transactional commerce, high-volume analytics, search and community feeds may eventually need different infrastructure.

The architecture should begin unified but maintain domain boundaries.

## 27.3 “No duplicated data”

No uncontrolled duplication is correct.

Some duplication is essential:

* order snapshots;
* analytics aggregates;
* cached read models;
* local mobile cache;
* external provider references.

The real rule should be:

**Each fact has one authority, while intentional projections and snapshots may exist.**

## 27.4 “Printify creates the product automatically from a design”

Not safely without product templates and validation.

Automation should remove repetitive work, not editorial judgment.

## 27.5 “Dodo Payments handles all payments”

This must not be assumed.

Before production physical-commerce integration, EAST. must verify:

* physical-goods eligibility;
* supported countries;
* shipping-address collection;
* tax responsibility;
* refunds;
* disputes;
* settlement currencies;
* Türkiye business eligibility;
* whether Dodo acts as merchant of record for this exact transaction type.

The current public documentation prominently describes checkout, billing, digital products and SaaS use cases; therefore physical-goods suitability requires explicit written confirmation before EAST. depends on it.

If Dodo does not properly support EAST.’s physical-goods model, the architecture remains unchanged and only the payment adapter is replaced.

## 27.6 “Supabase direct APIs eliminate the need for a backend”

Incorrect.

Supabase eliminates substantial infrastructure work.

EAST. still needs a server-side application layer for secrets, provider orchestration, transactions, idempotency, webhooks and business invariants.

---

# 28. Explicit Non-Goals for v1

Do not build initially:

* microservices;
* Kubernetes;
* GraphQL gateway;
* dedicated data warehouse;
* Elasticsearch;
* recommendation engine;
* full community system;
* complex loyalty points;
* discount engine with dozens of rule types;
* multi-vendor marketplace;
* custom payment processing;
* custom fulfilment network;
* visual page builder;
* large internal admin suite;
* remote executable app layouts.

These may become justified later.

They are not justified now.

---

# 29. Phased Implementation Plan

## Phase 0 — Protect the existing app

Before platform changes:

* tag the current Gold Master;
* document the locked ritual;
* capture regression videos;
* preserve transition and audio tests;
* document current local data keys;
* create a rollback point.

No backend integration begins until this protection exists.

## Phase 1 — Foundation

Build:

* monorepo structure;
* Supabase local/staging/production environments;
* migration system;
* profiles;
* installations;
* RLS baseline;
* API contract package;
* logging and error conventions;
* CI validation;
* architecture decision records.

No commerce yet.

## Phase 2 — Content and ritual synchronization

Build:

* canonical wisdom model;
* remote content versioning;
* local-first sync;
* ritual completion synchronization;
* cross-device reflection model;
* optional account linking;
* safe migration from current local state.

The visible ritual remains unchanged.

## Phase 3 — Website foundation

Build:

* Next.js editorial shell;
* homepage;
* Essays;
* Journal;
* Objects discovery;
* design tokens;
* public content API;
* SEO and metadata;
* cache invalidation.

No checkout until catalog modeling is stable.

## Phase 4 — Catalog and Printify synchronization

Build:

* EAST. products;
* variants;
* media;
* collections;
* provider mappings;
* Printify draft synchronization;
* product templates;
* synchronization jobs;
* minimal publication approval.

## Phase 5 — Physical commerce

Only after payment-provider suitability is confirmed:

* carts;
* checkout sessions;
* payment webhooks;
* orders;
* order snapshots;
* Printify fulfilment;
* tracking;
* refunds;
* reconciliation;
* customer order pages.

## Phase 6 — Mobile Objects

Add:

* remote Objects catalog;
* separate commerce navigation;
* physical checkout;
* order tracking;
* no ritual interruption.

## Phase 7 — Analytics and operations

Build:

* event taxonomy;
* commerce funnel;
* ritual retention;
* product conversion;
* materialized reports;
* operational alerts;
* dead-letter review;
* minimal admin health views.

## Phase 8 — Future ecosystem

Possible additions:

* journal system;
* curated member profiles;
* carefully designed community;
* physical-digital object relationships;
* desktop experience;
* public content API;
* additional fulfilment providers;
* dedicated analytics warehouse;
* search infrastructure.

---

# 30. Required Gates Before Coding

The following decisions must be finalized before implementation begins.

## Product decisions

* Are EAST. accounts optional or eventually mandatory?
* Can anonymous ritual history be merged into an account?
* Will Objects be available inside the mobile app at launch?
* Are essays available in the app, website or both?
* What exactly qualifies as an EAST. Object?

## Commerce decisions

* Is Dodo confirmed in writing to support EAST.’s physical-goods flow?
* Which entity legally sells the Objects?
* Which countries can buy initially?
* Who handles taxes, refunds and disputes?
* Which currencies are displayed and settled?
* What is the return policy for print-on-demand items?

## Content decisions

* Does every wisdom have a stable canonical ID?
* Can wisdom text be corrected after publication?
* How are old ritual records affected by corrections?
* Which languages are planned within two years?

## Privacy decisions

* Are reflections cloud-synchronized by default or opt-in?
* How long are raw analytics events retained?
* Is reflection export required?
* Is account deletion immediate or delayed for recovery?
* Which financial data must be legally retained?

---

# 31. Final Architectural Laws

1. **The ritual never waits for commerce.**
2. **The ritual never waits for a network call.**
3. **Supabase is the operational source of truth.**
4. **External providers are adapters, not the domain model.**
5. **Payments do not directly grant access; entitlements do.**
6. **Orders preserve immutable historical snapshots.**
7. **Every external mutation is idempotent.**
8. **Every webhook is verified, stored and deduplicated.**
9. **Every privileged operation runs server-side.**
10. **Every exposed table uses least-privilege RLS.**
11. **Every schema change is a migration in Git.**
12. **Every product can change without an App Store update.**
13. **Remote content may change; remote executable UI may not.**
14. **Analytics never receives reflection content.**
15. **Automation removes repetition, not brand judgment.**
16. **One editorial approval is preferable to accidental publication.**
17. **No service is extracted until real scale or risk requires it.**
18. **Every important business fact has one authority.**
19. **Caches and snapshots are deliberate projections, not competing truths.**
20. **Anything that threatens the quietness of EAST. is architecturally incorrect.**

---

# 32. Architecture v1.0 Verdict

The proposed technology stack is broadly appropriate.

The strongest long-term design is:

* Supabase/PostgreSQL as the core;
* local-first Flutter ritual;
* Next.js as the editorial web experience;
* a provider-neutral commerce and fulfilment domain;
* Printify behind a fulfilment adapter;
* Dodo behind a payment adapter only after physical-commerce eligibility is confirmed;
* StoreKit retained for iOS digital entitlements;
* event-driven automation using transactional outbox, queues, scheduled reconciliation and verified webhooks;
* minimal administration;
* explicit publication approval;
* gradual evolution from a modular monolith.

This structure allows EAST. to grow from one quiet mobile ritual into a connected platform of wisdom, editorial content and physical Objects without forcing the ritual itself to become complicated.

The backend may become sophisticated.

The user must never feel that sophistication.

That is the architecture.

---

# 33. Build 26 Addendum — iOS-Native Persistence Boundary

**See ADR-007** (`docs/decisions/ADR-007-build-26-local-storage-and-icloud-sync.md`) for the full, authoritative decision, and **see `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`** (Phase 4A) for the precise sync-domain design — CloudKit record model, local-first behavior, conflict/deletion rules, account-boundary behavior, and the native bridge contract that implement ADR-007's decision.

Build 26 introduces protected local storage and private Apple CloudKit synchronization for **both** Kept wisdoms and their attached Reflections, ahead of and independent from the Supabase/PostgreSQL platform described in Sections 1–32 above. This section exists only to state the boundary explicitly, so the two documents are never read as being in tension. **Kept and Reflections are not modeled or synced separately** — a Reflection is a field of the `KeptRecord` it belongs to, never a standalone entity — so there is no valid reading of this document, ADR-007, or `EAST_CLOUDKIT_SYNC_V1.md` in which only Reflections sync while Kept wisdoms remain local-only, or vice versa. Any such statement, wherever it may have appeared in earlier drafts or discussion, is superseded by this section.

The authoritative Build 26 sync posture:

* **Both Kept wisdoms and their attached Reflections sync through the user's private CloudKit database** — one CloudKit record per saved reveal occurrence, carrying both the Kept content and, when present, its Reflection. Neither syncs independently of the other.
* **Both remain cached locally in protected storage** (the local state envelope described in ADR-007) — CloudKit is never read directly by the UI.
* **Local protected storage is the application's immediate source for UI rendering.** Every screen reads and writes local state first and synchronously; CloudKit involvement is invisible to the UI and never blocks a read, a Keep, an edit, or a delete.
* **CloudKit is the cross-device replication layer, not the live UI database.** No screen queries CloudKit directly, waits on a CloudKit round-trip, or renders CloudKit state that has not already been applied to local protected storage first.
* **Daily access and the rolling 24-hour ritual lock remain local-only**, in every form — the record, the lock, `revealedAt`/`unlockAt`, current ritual screen/animation state, ritual eligibility, any pending daily reveal, private diagnostics, and analytics data. None of this is ever represented in a CloudKit record, an outbox entry, or any sync-domain model. This is unaffected by, and unrelated to, this addendum or Section 5's local-first ritual principle.
* **No EAST. account, sign-in system, or third-party backend is introduced by this feature** — synchronization relies solely on the user's own private, per-device-authenticated iCloud account, and does not alter Section 6's "accounts remain optional" posture.
* **No Reflection text or wisdom content ever enters analytics or diagnostics**, in this feature or any other — see ADR-007's Analytics boundary and `EAST_CLOUDKIT_SYNC_V1.md`'s privacy rules for the structural mechanisms that enforce this.
* **The stable `revealId` is the occurrence identity carried through, unchanged, across local storage and CloudKit** — never regenerated, never derived from wisdom text or a displayed date, and never mutated once a record has entered protected local storage or CloudKit. Exact duplicate wisdom text across distinct occurrences (the same text on different days, or Kept more than once) is expected and always remains distinct by `revealId`.
* **Uninstalling and reinstalling the app may reset local daily ritual access** (a new wisdom may become available sooner than the prior device's 24-hour lock would have allowed — an accepted, explicit tradeoff, not a defect) **but must restore Kept wisdoms and Reflections** once the reinstalled app signs into the same private iCloud account and completes a sync.
* **The app remains fully usable, including the daily ritual, when iCloud is unavailable, restricted, or absent** — CloudKit sync is strictly additive and asynchronous; no feature required for the ritual or for reading/editing/deleting existing local Kept content depends on network access or an iCloud account.
* Does **not** replace or pre-empt the `reflections`, `kept_reflections`, or `user_wisdom_favorites` tables described in Section 8.2 — those remain the intended eventual model once the platform in Sections 1–12 is built; migrating CloudKit-synced content into that future platform is a deliberately separate, later decision.
* Does **not** create cross-platform (Android or web) synchronization of any kind, and does **not** commit EAST. to CloudKit as the synchronization mechanism for any future platform, client, or data domain beyond this one iOS feature.

Where this addendum and any earlier section could otherwise be read as implying that all reflection/favorite synchronization must run through the future backend, ADR-007 and `EAST_CLOUDKIT_SYNC_V1.md` take precedence for the specific, narrow scope of Kept wisdoms and Reflections on iOS until the platform described above exists and a deliberate migration decision is made.
