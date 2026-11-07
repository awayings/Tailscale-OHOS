import { bundleManager } from '@kit.AbilityKit';

/**
 * The bundleName in AppScope/app.json5 is this app's identity for the whole
 * system: install/signature verification, Want routing (VPN ExtensionAbility,
 * notification WantAgents, background task agents) and the VPN config's
 * trusted/blocked application lists all match on it.
 *
 * Reading it at runtime keeps a forked or renamed build working without
 * hunting down every string literal. The fallback covers early process startup
 * and is checked against app.json5 by scripts/test-bundle-name.mjs.
 */
export const FALLBACK_BUNDLE_NAME: string = 'io.github.tailscale.homer';

export class AppIdentity {
  private static cachedBundleName: string = '';

  static bundleName(): string {
    if (AppIdentity.cachedBundleName.length > 0) {
      return AppIdentity.cachedBundleName;
    }
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (info.name.length > 0) {
        AppIdentity.cachedBundleName = info.name;
        return info.name;
      }
    } catch (_error) {
      // Bundle service can be unavailable during very early process startup.
    }
    return FALLBACK_BUNDLE_NAME;
  }
}
