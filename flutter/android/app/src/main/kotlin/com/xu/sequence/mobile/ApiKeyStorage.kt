package com.xu.sequence.mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class ApiKeyStorage(context: Context) {
    private val file = AtomicFile(File(context.noBackupFilesDir, "ai-key"))
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun read(): String? {
        val record = try {
            file.readFully()
        } catch (_: FileNotFoundException) {
            return null
        }
        val key = store.getKey(ALIAS, null) as? SecretKey ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, record, 0, NONCE_BYTES))
        return cipher.doFinal(record, NONCE_BYTES, record.size - NONCE_BYTES).toString(Charsets.UTF_8)
    }

    fun write(value: String): Boolean {
        if (value.isEmpty()) {
            store.deleteEntry(ALIAS)
            file.delete()
            return true
        }
        val key = store.getKey(ALIAS, null) as? SecretKey
            ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                init(
                    KeyGenParameterSpec.Builder(
                        ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build(),
                )
                generateKey()
            }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val record = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(cipher.iv.size == NONCE_BYTES)
        val output = file.startWrite()
        try {
            output.write(record)
            file.finishWrite(output)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
        return true
    }

    companion object {
        private const val ALIAS = "xu.ai-key"
        private const val NONCE_BYTES = 12
    }
}
