# Google Play Store Submission Guide

This document explains how to submit WLED Audio Sender to the Google Play Store after addressing the privacy policy requirement.

## Changes Made to Address Google Play Rejection

1. **Privacy Policy Created**: A comprehensive privacy policy has been created at `PRIVACY_POLICY.md` that explains:
   - How the app uses microphone permission
   - What data is collected (none)
   - How audio is processed (locally only)
   - No third-party services or tracking

2. **Version Code Incremented**: The version code has been updated from `1` to `2` in `pubspec.yaml` (line 19: `version: 1.0.0+2`)

## Steps to Submit to Google Play Console

When submitting your app to the Google Play Console, you must provide the privacy policy URL. Follow these steps:

### 1. Navigate to App Content

1. Log into [Google Play Console](https://play.google.com/console)
2. Select your app
3. Go to **Policy** → **App content** (in the left sidebar)

### 2. Add Privacy Policy URL

In the "Privacy policy" section:
1. Click **Start** or **Manage** (if you've already started this section)
2. Enter the Privacy Policy URL:
   ```
   https://github.com/netmindz/WLED-Audio-Sender/blob/main/PRIVACY_POLICY.md
   ```
3. Click **Save**

### 3. Review Data Safety Section

While you're in App content, also review the **Data safety** section:
1. Click **Start** or **Manage**
2. Answer the questions about data collection:
   - **Does your app collect or share any of the required user data types?** → Select **No**
   - The app doesn't collect or share any user data
3. Save your responses

### 4. Build and Upload New APK/AAB

Build the new version with the incremented version code:

```bash
# For APK
flutter build apk --release

# For App Bundle (recommended)
flutter build appbundle --release
```

Upload the new APK or App Bundle to the Google Play Console:
1. Go to **Release** → **Production** (or your desired track)
2. Click **Create new release**
3. Upload your APK/AAB
4. Add release notes mentioning the privacy policy addition
5. Review and roll out

### 5. Submit for Review

After completing all required sections:
1. Review all policy sections to ensure they're marked as complete
2. Submit your app for review

## Important Notes

- **Version Code**: The app now uses version code `2` (increased from `1`)
- **Privacy Policy URL**: Must be publicly accessible (GitHub URL works)
- **Microphone Permission**: The `RECORD_AUDIO` permission is required for the app's core functionality
- **No Data Collection**: The app doesn't collect any personal data, which simplifies the data safety form

## Alternative Privacy Policy Hosting

While the GitHub URL works, you can also:
1. Host the privacy policy on your own website
2. Convert `PRIVACY_POLICY.md` to HTML and host it anywhere
3. Use GitHub Pages for a more polished presentation

If you host it elsewhere, update the URL in:
- Google Play Console → App content → Privacy policy
- `README.md` (optional, for consistency)

## Troubleshooting

### "Privacy policy URL not accessible"
- Ensure the URL is publicly accessible (no login required)
- GitHub raw content URLs may not work; use the regular GitHub URL instead
- Test the URL in an incognito browser window

### "Version code already used"
- The version code has been incremented to `2`
- If you need to submit again, increment the version code in `pubspec.yaml`
- Format: `version: MAJOR.MINOR.PATCH+BUILD_NUMBER`
- Example for next release: `version: 1.0.0+3`

### "Sensitive permissions require additional information"
- Complete the Data safety section in App content
- Explain that microphone is used for audio synchronization
- Confirm no data is collected or shared

## Contact

For questions about this process, please create an issue on the GitHub repository:
https://github.com/netmindz/WLED-Audio-Sender/issues
