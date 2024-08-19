package com.microsoft.codepush.react;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;

interface MultiBundleInterface {
    String bundleResourceSubdirectory(String subdirectory);
    String getCodePushPath();
    String preferenceKeyWrap(String key);
    String getMultiBundleHead();
    boolean switchBundle(String head);
    String getDeploymentKey(String originKey);
}
public final class CodePushConfig implements MultiBundleInterface {
    // Native current bundle HEAD
    private String mMultiBundlesHead;
    // Supported bundle list
    private ArrayList<Map<String, String>> mMultiBundles;
    private static final String ASSETS_DEPLOYMENTS_JSON_FILE = "deployments.json";
    private static final String DEPLOYMENT_NAME = "deploymentName";
    private static final String DEPLOYMENT_KEY = "deploymentKey";
    private final Context mContext;
    private SharedPreferences mPreferences;
    private static CodePushConfig mCurrent;

    private CodePushConfig(Context context) {
        this.mPreferences = context.getSharedPreferences(CodePushConstants.CODE_PUSH_PREFERENCES, 0);
        this.mContext = context.getApplicationContext();
        this.initialize();
    }

    public static CodePushConfig current(Context context) {
        if (mCurrent == null) {
            mCurrent = new CodePushConfig(context);
        }
        return mCurrent;
    }

    // PUBLIC METHODS
    // 获取 head
    private String getMultiBundlesHead() {
        return mPreferences.getString(CodePushConstants.MULTI_BUNDLES_HEAD, null);
    }

    // 写入 head
    private void saveMultiBundlesHead(String head) {
        mPreferences.edit().putString(CodePushConstants.MULTI_BUNDLES_HEAD, head).commit();
    }
    // 是否处于多 bundle 模式
    private boolean isMultiBundlesMode() {
        return !this.mMultiBundles.isEmpty();
    }

    // 内置 bundle 的子目录，如果多 bundle 下，会追加前缀 /deployments
    // 否则原样返回
    @Override
    public String bundleResourceSubdirectory(String subdirectory) {
        if (this.isMultiBundlesMode()) {
            return String.format("deployments/%s/%s", this.mMultiBundlesHead, subdirectory);
        }
        return subdirectory;
    }

    // 下载文件保存到的目录，多 bundle 下，追加前缀 /CodePush/{deploymentName}
    // 否则返回 /CodePush
    @Override
    public String getCodePushPath() {
        if (this.isMultiBundlesMode()) {
            return String.format("%s/%s", CodePushConstants.CODE_PUSH_FOLDER_PREFIX, this.mMultiBundlesHead);
        }
        return String.format("%s", CodePushConstants.CODE_PUSH_FOLDER_PREFIX);
    }

    // 所有 pref CRUD 读写的 key 需隔离的，都需要套一层该函数调用
    @Override
    public String preferenceKeyWrap(String key) {
        if (this.isMultiBundlesMode()) {
            return String.format("%s%s", key, this.mMultiBundlesHead);
        }
        return key;
    }

    // 判断是否 head 在 deployments 列表，如果在返回 index
    // 否则返回 -1
    private int indexOfBundleHead(String head) {
        if (this.mMultiBundles == null) return -1;
        for (int i = 0; i < this.mMultiBundles.size(); i++) {
            final Map<String, String> bundle = this.mMultiBundles.get(i);
            final String key = bundle.get(DEPLOYMENT_NAME);
            if (Objects.equals(key, head)) return i;
        }
        return -1;
    }

    // 设置 head
    private void setMultiBundleHead(String head) {
        if (!this.isMultiBundlesMode()) return;

        this.mMultiBundlesHead = head;
        this.saveMultiBundlesHead(head);
    }

    @Override
    public String getMultiBundleHead() {
        return mMultiBundlesHead;
    }

    // 切换 bundle
    @Override
    public boolean switchBundle(String head) {
        if (head == null) return false;
        if (!this.isMultiBundlesMode()) return false;
        if (this.indexOfBundleHead(head) == -1) return false;
        if (Objects.equals(this.mMultiBundlesHead, head)) return false;

        this.setMultiBundleHead(head);
        return true;
    }

    // 获取 deploymentKey
    @Override
    public String getDeploymentKey(String deploymentKey) {
        if (this.isMultiBundlesMode()) {
            final int idx = this.indexOfBundleHead(this.mMultiBundlesHead);
            if (idx > -1) {
                final Map<String, String> bundle = this.mMultiBundles.get(idx);
                return bundle.get(DEPLOYMENT_KEY);
            }
        }
        return deploymentKey;
    }

    // 初始化多 bundle props： mMultiBundles, mMultiBundlesHead
    private void initialize() {
        this.mMultiBundles = this.loadDeploymentsJson();
        this.mMultiBundlesHead = this.getMultiBundlesHead();

        if (!this.mMultiBundles.isEmpty() && this.mMultiBundlesHead == null) {
            // 第一次运行，没有 head 指针，将 head 指向第一个 bundle deployment name
            final Map<String, String> fallbackDeployment = this.mMultiBundles.get(0);
            final String name = fallbackDeployment.get(DEPLOYMENT_NAME);

            this.saveMultiBundlesHead(name);
            this.setMultiBundleHead(name);
        } else if (this.mMultiBundles.isEmpty()) {
            // 多 bundle 切换到单 bundle，清空 head
            this.mMultiBundlesHead = null;
            this.setMultiBundleHead(null);
        }
    }

    // CI 会将 deployments 配置到 assets/deployments.json 中，这里读取到内存
    private ArrayList<Map<String, String>> loadDeploymentsJson() {
        String json = null;
        InputStream is = null;
        try {
            is = mContext.getAssets().open(ASSETS_DEPLOYMENTS_JSON_FILE);
            int size = is.available();
            byte[] buffer = new byte[size];
            is.read(buffer);
            json = new String(buffer, StandardCharsets.UTF_8);
        } catch(IOException e) {
            json = "[]";
        } finally {
            if (is != null) try { is.close(); } catch (IOException ignored) {}
        }

        try {
            return getDeploymentsFromJson(json);
        } catch (JSONException e) {
            return new ArrayList<>();
        }
    }

    // JSON String -> ArrayList<Map<String, String>>
    @NonNull
    private static ArrayList<Map<String, String>> getDeploymentsFromJson(String json) throws JSONException {
        final JSONArray deployments = new JSONArray(json);
        final ArrayList<Map<String, String>> result = new ArrayList<>();
        for (int i = 0; i < deployments.length(); i++) {
            final JSONObject deployment = deployments.getJSONObject(i);
            final String deploymentName = deployment.getString(DEPLOYMENT_NAME);
            final String deploymentKey = deployment.getString(DEPLOYMENT_KEY);
            final Map<String, String> map = new HashMap<>();
            map.put(DEPLOYMENT_NAME, deploymentName);
            map.put(DEPLOYMENT_KEY, deploymentKey);
            result.add(map);
        }
        return result;
    }
}
