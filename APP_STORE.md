# Put Sugerly on the App Store (from Windows)

You don't need a Mac. GitHub's Macs build, sign and upload the app. You
only use a web browser, plus your iPhone for testing.

Budget: **$99 / year** (Apple Developer Program) and about an hour of
clicking, spread over a few days while Apple approves things.

---

## 1. Join the Apple Developer Program

1. Go to <https://developer.apple.com/programs/enroll/> and sign in with
   your Apple ID. It needs two-factor authentication, which your iPhone
   already does.
2. Enroll as an **Individual**. Pay the $99.
3. Wait for the "Welcome to the Apple Developer Program" email. It usually
   takes a few hours and sometimes up to 2 days.

## 2. Merge the pull request

On GitHub, open **Pull requests → #1 → Merge pull request**.

This puts the final code and the "Upload to App Store" button on your
main branch.

## 3. Put the Privacy Policy and Help pages online (free)

Apple needs two web links. The site built from this repo shows **only**
Help & FAQ, Terms, Privacy and Guidelines. Sugerly itself stays an
iPhone/iPad app.

1. Go to <https://app.netlify.com> and sign up with GitHub.
2. Click **Add new site → Import an existing project → GitHub**, then pick
   this repo and the `main` branch.
3. Click **Deploy**. The settings come from `netlify.toml`, so don't
   change anything.
4. Optionally, rename the site under **Site configuration → Change site
   name**, for example to `sugerly`.

Your links are:

- Privacy Policy: `https://sugerly.netlify.app/Legal/privacy`
- Support: `https://sugerly.netlify.app/Help`

## 4. Create the app in App Store Connect

1. Go to <https://appstoreconnect.apple.com> → **Apps → + → New App**.
2. Fill in:
   - **Platform:** iOS
   - **Name:** Sugerly (if the name is taken, try "Sugerly – Art & Reels")
   - **Language:** English (U.S.)
   - **Bundle ID:** pick **com.mimilocks.app**. If it isn't in the list, first
     register it at developer.apple.com → Certificates, IDs & Profiles →
     Identifiers → + → App IDs → App, with Bundle ID `com.mimilocks.app`
     (explicit).
   - **SKU:** `sugerly-ios-1`
   - **User access:** Full

## 5. Make an API key so GitHub can upload for you

1. In App Store Connect, go to **Users and Access → Integrations →
   App Store Connect API**.
2. Click **Team Keys → Generate API Key**. Name it `GitHub` and give it the
   **Admin** role. Admin is needed so it can create the signing certificate
   for you.
3. **Download** the `.p8` file. You can only download it once. Also note
   the **Key ID** and the **Issuer ID** shown on that page.
4. Find your **Team ID**: developer.apple.com → Account → Membership
   details (10 characters).

## 6. Give GitHub the 4 secrets

On GitHub, open the repo → **Settings → Secrets and variables → Actions →
New repository secret**, and add these four:

| Name | Value |
| --- | --- |
| `APPLE_TEAM_ID` | your Team ID |
| `APP_STORE_CONNECT_KEY_ID` | the Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID |
| `APP_STORE_CONNECT_KEY` | open the `.p8` file in Notepad and paste **all** of it, including the BEGIN/END lines |

Never paste these anywhere else, including chats.

## 7. Upload the app

1. On GitHub, go to **Actions → Upload to App Store → Run workflow**. Leave
   the version at `1.0`, then click **Run**.
2. Wait about 15 minutes for the green check. If it goes red, open the run
   and read the error at the bottom.
3. The build shows up in App Store Connect → your app → **TestFlight**
   about 10–30 minutes later.

## 8. Test it on your iPhone (TestFlight)

1. In App Store Connect → TestFlight, add yourself under **Internal
   Testing**.
2. Install **TestFlight** from the App Store on your iPhone, open the
   invite, and install Sugerly.
3. In the app, **sign up a test account for Apple's reviewer**, for example
   `review@yourname.test` with a password. Post something so the account
   isn't empty. You'll give these details to Apple in the next step.

## 9. Fill in the store page and submit

Open your app in App Store Connect and copy everything from
[`appstore/listing.md`](appstore/listing.md):

- Description, keywords, promotional text, support and privacy URLs
- Screenshots from `appstore/screenshots/` (download them from GitHub)
- **App Privacy** answers
- **Age Rating** answers
- **App Review Information**: the test account from step 8 and the notes
- Under **Build**, pick the build from step 7

Then click **Add for Review → Submit**. Review usually takes 1–3 days.
When it's approved, press **Release**.

---

## Updates later

Change the app, merge to `main`, then **Actions → Upload to App Store →
Run workflow** with a higher version (e.g. `1.1`). After that, create a new
version in App Store Connect, pick the new build, and submit.

## Before you submit — the rules you promised

- The Terms say reports are reviewed **within 24 hours**. Check
  **Admin → Reports** every day. Support messages from the in-app
  "Contact us" form show up there too, and you answer them by DM.
- Have someone read the Terms and Privacy Policy. They are a good starting
  point written for how Sugerly works, but they are not legal advice.
