# Flow Plus Payment Testing

Flow includes a checked-in local StoreKit configuration at `StoreKit/FlowPlus.storekit` for the monthly Flow Plus subscription.

## Local Xcode testing

1. Open the `Flow` scheme in Xcode.
2. Confirm `Run > Options > StoreKit Configuration` is set to `FlowPlus.storekit`.
3. Run the app on the simulator.
4. Open `Settings > Flow Plus` or the Sakura lock state and tap `Unlock Flow Plus`.
5. Complete the StoreKit sheet. Xcode will simulate the monthly subscription for `com.21media.flow.flowplus.monthly`.

Notes:
- Local StoreKit config purchases do not charge real money.
- The local config is only for Xcode-run builds and is not shipped in App Store releases.
- To reset local purchases, use Xcode's StoreKit transaction manager while the app is running.

## Sandbox testing

After App Store Connect is configured:

1. Create the app record using bundle ID `com.21media.flow`.
2. Create a subscription group named `Flow Plus`.
3. Add the auto-renewable subscription `com.21media.flow.flowplus.monthly` at `$5.99/month`.
4. Create a Sandbox Apple Account in App Store Connect.
5. Sign into that sandbox account on the test device.
6. Run a development build or TestFlight build and purchase Flow Plus.

Notes:
- Sandbox and TestFlight purchases also do not charge real money.
- `Restore Purchases` in the paywall calls `AppStore.sync()` and should restore the subscription entitlement.
