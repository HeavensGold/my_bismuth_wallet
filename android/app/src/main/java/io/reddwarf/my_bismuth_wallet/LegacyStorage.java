package io.reddwarf.my_bismuth_wallet;

public class LegacyStorage {
    public String getSecret() {
        // Return empty string as legacy storage is no longer used
        // App now uses secure storage via Flutter plugin
        return "";
    }
}