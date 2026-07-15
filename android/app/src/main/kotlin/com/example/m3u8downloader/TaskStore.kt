package com.example.m3u8downloader

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object TaskStore {
    private const val PREFS = "download_tasks"
    private const val KEY = "tasks"
    private const val MAX_TASKS = 100

    @Synchronized
    fun upsert(context: Context, task: JSONObject) {
        val tasks = readArray(context)
        val updated = JSONArray().put(task)
        for (index in 0 until tasks.length()) {
            val existing = tasks.optJSONObject(index) ?: continue
            if (existing.optString("id") != task.optString("id") && updated.length() < MAX_TASKS) {
                updated.put(existing)
            }
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, updated.toString())
            .apply()
    }

    @Synchronized
    fun getTasks(context: Context): List<Map<String, Any>> {
        val tasks = readArray(context)
        val localFiles = LocalDownloads.list(context)
        val result = buildList {
            for (index in 0 until tasks.length()) {
                tasks.optJSONObject(index)?.let { task ->
                    val fallbackTime = task.optString("id").substringBefore('-').toLongOrNull() ?: 0L
                    if (!task.has("createdAt")) task.put("createdAt", fallbackTime)
                    if (!task.has("completedAt")) {
                        task.put(
                            "completedAt",
                            if (task.optString("status") == "completed") fallbackTime else 0L,
                        )
                    }
                    val localFile = localFiles
                        .filter { it.displayName == task.optString("fileName") }
                        .maxByOrNull { it.addedAt }
                    if (task.optLong("fileSize") <= 0L && localFile != null) {
                        task.put("fileSize", localFile.size)
                    }
                    if (task.optString("contentUri").isBlank() && localFile != null) {
                        task.put("contentUri", localFile.uri.toString())
                    }
                    if (!task.has("contentUri")) task.put("contentUri", "")
                    if (!task.has("uploaded")) task.put("uploaded", false)
                    add(jsonToMap(task.toString()))
                }
            }
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, tasks.toString())
            .apply()
        return result
    }

    @Synchronized
    fun markUploaded(context: Context, ids: Set<String>): List<JSONObject> {
        val tasks = readArray(context)
        val updated = mutableListOf<JSONObject>()
        for (index in 0 until tasks.length()) {
            val task = tasks.optJSONObject(index) ?: continue
            if (task.optString("id") in ids) {
                task.put("uploaded", true)
                task.put("uploadedAt", System.currentTimeMillis())
                updated += task
            }
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, tasks.toString())
            .apply()
        return updated
    }

    @Synchronized
    fun delete(context: Context, ids: Set<String>) {
        val tasks = readArray(context)
        val retained = JSONArray()
        for (index in 0 until tasks.length()) {
            val task = tasks.optJSONObject(index) ?: continue
            if (task.optString("id") !in ids) retained.put(task)
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, retained.toString())
            .apply()
    }

    fun jsonToMap(json: String): Map<String, Any> {
        val value = JSONObject(json)
        return buildMap {
            value.keys().forEach { key -> put(key, value.opt(key) ?: "") }
        }
    }

    private fun readArray(context: Context): JSONArray {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        return try {
            if (raw == null) JSONArray() else JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

}
