package com.adbmanage.helper;

import android.content.pm.PackageInfo;
import android.content.pm.Signature;
import android.os.Build;

import java.io.ByteArrayInputStream;
import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;

/** 读取当前及历史 signer，并将 X.509 证书详情序列化为 Helper JSON。 */
final class PackageSignatureReader {
    private PackageSignatureReader() {}

    static String getPrimaryMd5(PackageInfo packageInfo) {
        try {
            Signature[] signatures = getCurrentSignatures(packageInfo);
            if (signatures == null || signatures.length == 0) {
                return "";
            }
            return fingerprint(signatures[0].toByteArray(), "MD5");
        } catch (Throwable ignored) {
            return "";
        }
    }

    static String toJson(PackageInfo packageInfo) {
        List<CertificateInfo> certificates = readCertificates(packageInfo);
        StringBuilder json = new StringBuilder("[");
        for (int index = 0; index < certificates.size(); index++) {
            if (index > 0) json.append(",");
            CertificateInfo certificate = certificates.get(index);
            json.append("{");
            json.append("\"current\":").append(certificate.current).append(",");
            json.append("\"certificateVersion\":").append(certificate.certificateVersion).append(",");
            json.append("\"serialNumber\":\"").append(escapeJson(certificate.serialNumber)).append("\",");
            json.append("\"subject\":\"").append(escapeJson(certificate.subject)).append("\",");
            json.append("\"issuer\":\"").append(escapeJson(certificate.issuer)).append("\",");
            json.append("\"notBefore\":").append(certificate.notBefore).append(",");
            json.append("\"notAfter\":").append(certificate.notAfter).append(",");
            json.append("\"signatureAlgorithm\":\"").append(escapeJson(certificate.signatureAlgorithm)).append("\",");
            json.append("\"publicKeyAlgorithm\":\"").append(escapeJson(certificate.publicKeyAlgorithm)).append("\",");
            json.append("\"md5\":\"").append(certificate.md5).append("\",");
            json.append("\"sha1\":\"").append(certificate.sha1).append("\",");
            json.append("\"sha256\":\"").append(certificate.sha256).append("\"");
            json.append("}");
        }
        return json.append("]").toString();
    }

    private static List<CertificateInfo> readCertificates(PackageInfo packageInfo) {
        List<CertificateInfo> result = new ArrayList<>();
        Signature[] currentSignatures = getCurrentSignatures(packageInfo);
        Signature[] allSignatures = currentSignatures;

        if (Build.VERSION.SDK_INT >= 28 && packageInfo.signingInfo != null
                && !packageInfo.signingInfo.hasMultipleSigners()) {
            Signature[] history = packageInfo.signingInfo.getSigningCertificateHistory();
            if (history != null && history.length > 0) {
                allSignatures = history;
            }
        }
        if (allSignatures == null) {
            return result;
        }

        HashSet<String> seen = new HashSet<>();
        for (Signature signature : allSignatures) {
            if (signature == null) continue;
            byte[] encoded = signature.toByteArray();
            String sha256 = fingerprint(encoded, "SHA-256");
            if (!seen.add(sha256)) continue;

            CertificateInfo info = new CertificateInfo();
            info.current = containsSignature(currentSignatures, signature);
            info.md5 = fingerprint(encoded, "MD5");
            info.sha1 = fingerprint(encoded, "SHA-1");
            info.sha256 = sha256;
            try {
                X509Certificate certificate = (X509Certificate) CertificateFactory
                        .getInstance("X.509")
                        .generateCertificate(new ByteArrayInputStream(encoded));
                info.subject = certificate.getSubjectX500Principal().getName();
                info.issuer = certificate.getIssuerX500Principal().getName();
                info.serialNumber = certificate.getSerialNumber().toString(16).toUpperCase(Locale.US);
                info.notBefore = certificate.getNotBefore().getTime();
                info.notAfter = certificate.getNotAfter().getTime();
                info.certificateVersion = certificate.getVersion();
                info.signatureAlgorithm = certificate.getSigAlgName();
                info.publicKeyAlgorithm = certificate.getPublicKey().getAlgorithm();
            } catch (Throwable ignored) {
                // X.509 解析失败时仍保留可用的证书指纹。
            }
            result.add(info);
        }
        return result;
    }

    private static Signature[] getCurrentSignatures(PackageInfo packageInfo) {
        if (Build.VERSION.SDK_INT >= 28 && packageInfo.signingInfo != null) {
            Signature[] signers = packageInfo.signingInfo.getApkContentsSigners();
            if (signers != null && signers.length > 0) return signers;
        }
        return packageInfo.signatures;
    }

    private static boolean containsSignature(Signature[] signatures, Signature target) {
        if (signatures == null) return false;
        for (Signature signature : signatures) {
            if (target.equals(signature)) return true;
        }
        return false;
    }

    private static String fingerprint(byte[] encoded, String algorithm) {
        try {
            byte[] digest = MessageDigest.getInstance(algorithm).digest(encoded);
            StringBuilder value = new StringBuilder();
            for (byte item : digest) {
                value.append(String.format(Locale.US, "%02x", item & 0xff));
            }
            return value.toString();
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static String escapeJson(String value) {
        if (value == null) return "";
        return value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private static final class CertificateInfo {
        private boolean current;
        private int certificateVersion;
        private String serialNumber = "";
        private String subject = "";
        private String issuer = "";
        private long notBefore;
        private long notAfter;
        private String signatureAlgorithm = "";
        private String publicKeyAlgorithm = "";
        private String md5 = "";
        private String sha1 = "";
        private String sha256 = "";
    }
}
