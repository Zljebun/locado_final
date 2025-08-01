// android/app/src/main/kotlin/com/example/locado_final/FileIntentPlugin.kt

package com.example.locado_final

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.database.Cursor
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class FileIntentPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val CHANNEL = "com.example.locado_final/file_intent"
        private const val TAG = "FileIntentPlugin"
    }
    
    private var methodChannel: MethodChannel? = null
    private var pendingFileIntent: Intent? = null
    
    fun setupChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler(this)
        
        android.util.Log.d(TAG, "FileIntentPlugin channel setup complete")
    }
    
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        when (call.method) {
            "getInitialFileIntent" -> {
                handleGetInitialFileIntent(result)
            }
            "getFilePathFromUri" -> {
                val uriString = call.arguments as? String
                if (uriString != null) {
                    handleGetFilePathFromUri(uriString, result)
                } else {
                    result.error("INVALID_ARGUMENT", "URI string is null", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
	fun handleFileIntent(intent: Intent) {
		android.util.Log.d(TAG, "Handling file intent: ${intent.action}")
		
		when (intent.action) {
			Intent.ACTION_VIEW -> {
				val uri = intent.data
				if (uri != null) {
					android.util.Log.d(TAG, "File URI: $uri")
					
					// ✅ ISPRAVKA: Provjeri sadržaj fajla umjesto imena
					if (isLocadoFile(uri)) {
						android.util.Log.d(TAG, "✅ Valid Locado file detected based on content")
						
						val intentData = mapOf(
							"action" to intent.action,
							"data" to uri.toString(),
							"type" to intent.type
						)
						
						if (methodChannel != null) {
							android.util.Log.d(TAG, "🔗 Sending to Flutter immediately")
							methodChannel?.invokeMethod("handleFileIntent", intentData)
						} else {
							android.util.Log.d(TAG, "📦 Storing for later - Flutter not ready")
							pendingFileIntent = intent
						}
					} else {
						android.util.Log.w(TAG, "❌ File is not a valid Locado file")
					}
				} else {
					android.util.Log.w(TAG, "❌ Intent data URI is null")
				}
			}
			else -> {
				android.util.Log.w(TAG, "❌ Unsupported intent action: ${intent.action}")
			}
		}
	}
	
	private fun isLocadoFile(uri: Uri): Boolean {
		return try {
			android.util.Log.d(TAG, "🔍 Checking file content for Locado format...")
			
			val inputStream = context.contentResolver.openInputStream(uri)
			if (inputStream != null) {
				// Čitaj prve 500 karaktera fajla
				val buffer = ByteArray(500)
				val bytesRead = inputStream.read(buffer)
				inputStream.close()
				
				if (bytesRead > 0) {
					val fileContent = String(buffer, 0, bytesRead)
					android.util.Log.d(TAG, "📄 File content preview: ${fileContent.substring(0, minOf(100, fileContent.length))}")
					
					// Provjeri da li sadrži Locado markere
					val hasLocadoVersion = fileContent.contains("locado_version")
					val hasExportType = fileContent.contains("task_share")
					val hasTaskData = fileContent.contains("task_data")
					
					android.util.Log.d(TAG, "🔍 Content validation:")
					android.util.Log.d(TAG, "  - locado_version: $hasLocadoVersion")
					android.util.Log.d(TAG, "  - task_share: $hasExportType") 
					android.util.Log.d(TAG, "  - task_data: $hasTaskData")
					
					return hasLocadoVersion && hasExportType && hasTaskData
				}
			}
			
			android.util.Log.w(TAG, "❌ Could not read file content")
			false
		} catch (e: Exception) {
			android.util.Log.e(TAG, "❌ Error checking file content: ${e.message}")
			false
		}
	}
    
    private fun handleGetInitialFileIntent(result: MethodChannel.Result) {
        android.util.Log.d(TAG, "🔍 Checking for pending file intent...")
        
        if (pendingFileIntent != null) {
            val intent = pendingFileIntent!!
            val uri = intent.data
            
            if (uri != null) {
                android.util.Log.d(TAG, "✅ Found pending intent: $uri")
                
                val intentData = mapOf(
                    "action" to intent.action,
                    "data" to uri.toString(),
                    "type" to intent.type
                )
                
                result.success(intentData)
                pendingFileIntent = null // Clear after handling
            } else {
                android.util.Log.d(TAG, "❌ Pending intent has no data")
                result.success(null)
            }
        } else {
            android.util.Log.d(TAG, "ℹ️ No pending file intent")
            result.success(null)
        }
    }
    
    private fun handleGetFilePathFromUri(uriString: String, result: MethodChannel.Result) {
        try {
            android.util.Log.d(TAG, "📁 Resolving file path from URI: $uriString")
            
            val uri = Uri.parse(uriString)
            val filePath = getFilePathFromUri(uri)
            
            if (filePath != null) {
                android.util.Log.d(TAG, "✅ Resolved file path: $filePath")
                result.success(filePath)
            } else {
                android.util.Log.e(TAG, "❌ Could not resolve file path from URI")
                result.error("FILE_ACCESS_ERROR", "Could not resolve file path from URI", null)
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Error resolving file path", e)
            result.error("FILE_ACCESS_ERROR", e.message, null)
        }
    }
    
    private fun getFilePathFromUri(uri: Uri): String? {
        return when (uri.scheme) {
            "file" -> {
                android.util.Log.d(TAG, "📂 Processing file:// URI")
                uri.path
            }
            "content" -> {
                android.util.Log.d(TAG, "📄 Processing content:// URI")
                getFilePathFromContentUri(uri)
            }
            else -> {
                android.util.Log.w(TAG, "❌ Unsupported URI scheme: ${uri.scheme}")
                null
            }
        }
    }
    
    private fun getFilePathFromContentUri(uri: Uri): String? {
        try {
            // Try to get file path directly from content resolver
            val cursor: Cursor? = context.contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val displayNameIndex = it.getColumnIndex("_display_name")
                    if (displayNameIndex >= 0) {
                        val fileName = it.getString(displayNameIndex)
                        android.util.Log.d(TAG, "📝 Content URI filename: $fileName")
                        
                        if (fileName.lowercase().endsWith(".locado")) {
                            // Copy file to cache directory for access
                            return copyUriToCache(uri, fileName)
                        }
                    }
                }
            }
            
            // Fallback: try to copy file based on URI
            val fileName = getFileName(uri) ?: "shared_task.locado"
            android.util.Log.d(TAG, "🔄 Fallback: copying file as $fileName")
            return copyUriToCache(uri, fileName)
            
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Error accessing content URI", e)
            return null
        }
    }
    
    private fun copyUriToCache(uri: Uri, fileName: String): String? {
        try {
            android.util.Log.d(TAG, "📋 Copying URI to cache: $fileName")
            
            val inputStream: InputStream? = context.contentResolver.openInputStream(uri)
            if (inputStream != null) {
                val cacheDir = File(context.cacheDir, "shared_files")
                if (!cacheDir.exists()) {
                    cacheDir.mkdirs()
                    android.util.Log.d(TAG, "📁 Created cache directory: ${cacheDir.absolutePath}")
                }
                
                val file = File(cacheDir, fileName)
                val outputStream = FileOutputStream(file)
                
                inputStream.use { input ->
                    outputStream.use { output ->
                        input.copyTo(output)
                    }
                }
                
                android.util.Log.d(TAG, "✅ File copied to cache: ${file.absolutePath}")
                return file.absolutePath
            } else {
                android.util.Log.e(TAG, "❌ Could not open input stream for URI")
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Error copying file to cache", e)
        }
        
        return null
    }
    
    private fun getFileName(uri: Uri): String? {
        var fileName: String? = null
        
        if (uri.scheme == "content") {
            try {
                val cursor = context.contentResolver.query(uri, null, null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val nameIndex = it.getColumnIndex("_display_name")
                        if (nameIndex >= 0) {
                            fileName = it.getString(nameIndex)
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e(TAG, "Error querying content resolver", e)
            }
        }
        
        if (fileName == null) {
            fileName = uri.path?.let { path ->
                val cut = path.lastIndexOf('/')
                if (cut != -1) {
                    path.substring(cut + 1)
                } else {
                    path
                }
            }
        }
        
        android.util.Log.d(TAG, "📄 Extracted filename: $fileName")
        return fileName
    }
}