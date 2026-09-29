# Commissions & card payments (Stripe)

Buyers pay artists by card (Apple Pay, Google Pay and more) through
[Stripe Checkout](https://stripe.com/payments/checkout). The money goes into
**your** Stripe account; Sugerly keeps a fee (10% by default, admins can change
it in Admin → Site) and you pay artists out.

## How an order works

1. **Request**: the buyer picks a size on a shop listing and describes what they want.
2. **Accept**: the artist accepts (and can set the final price) or declines.
3. **Pay**: the buyer pays by card on Stripe's secure page.
4. **Deliver**: the artist uploads the finished art.
5. **Approve**: the buyer approves it with a star rating and review. If something
   goes wrong, the buyer can ask for a refund, and an admin refunds it in one tap.
6. **Payout**: approved orders show up in **My shop → Admin · payouts**, grouped
   by artist with their PayPal email. Send the money, then tap
   *Mark as paid out*.

Only the payment server can mark an order paid (the database rules block
everyone else), so nobody can fake a payment.

## One-time setup (about 10 minutes)

1. Make a Stripe account at <https://dashboard.stripe.com/register> and finish
   the business details so you can accept live payments.
2. In Netlify: **Site configuration → Environment variables**, add:

   | Key | Value |
   | --- | --- |
   | `STRIPE_SECRET_KEY` | Stripe → Developers → API keys → **Secret key** (`sk_live_…`, or `sk_test_…` to try it with test cards first) |
   | `FIREBASE_CLIENT_EMAIL` | the `client_email` from your Firebase service-account key file |
   | `FIREBASE_PRIVATE_KEY` | the `private_key` from the same file (from `-----BEGIN` to `END PRIVATE KEY-----`) |

   You can also use `FIREBASE_SERVICE_ACCOUNT` with the whole key file instead
   of the two Firebase keys.
3. Redeploy the site (Deploys → Trigger deploy). The payment functions are in
   `netlify/functions` and deploy with the site.
4. **Recommended:** in Stripe → Developers → Webhooks, add the endpoint
   `https://sugerly.netlify.app/.netlify/functions/commission-webhook` for the
   event `checkout.session.completed`. Put its **signing secret** (`whsec_…`) in
   Netlify as `STRIPE_WEBHOOK_SECRET`. This marks orders paid even if the buyer
   closes the page right after paying. Without the webhook, orders are marked
   paid when the buyer comes back to Sugerly.

To test: use a `sk_test_…` key and the card `4242 4242 4242 4242` with any
future date and any CVC.

## The payment functions

| Function | What it does |
| --- | --- |
| `commission-checkout` | Starts a Stripe Checkout for an accepted order (only the buyer, only the agreed price). |
| `commission-confirm` | Asks Stripe whether a checkout was paid and marks the order paid. |
| `commission-webhook` | The same, driven by Stripe's webhook. |
| `commission-review` | Counts the rating and the sale on the artist's listing once the buyer approves. |
| `commission-refund` | Admins only: refunds the card payment and marks the order refunded. |

They use Stripe's and Firebase's web APIs directly, so no packages are needed.

## Notes

- Apple requires In-App Purchase for digital content bought inside App Store
  apps, except on the US storefront, where apps may link to their own checkout.
  So the App Store / TestFlight app only shows the Pay button to US App Store
  accounts; everywhere else buyers pay on the website. Sideloaded copies and
  the website always can pay by card.
- Selling coins for real money is not enabled; coins stay earned (daily
  rewards, invites, posting).
