package com.defo.fetchr

// Pure: where a MediaStore item lives, as a document id of the Files app's external storage provider.
internal object FolderPath {
    private const val PRIMARY = "primary:"

    // RELATIVE_PATH (API 29+) is the folder with a trailing slash: "Movies/Fetchr/".
    fun fromRelativePath(relativePath: String?): String? =
        relativePath?.trim('/')?.takeIf { it.isNotEmpty() }?.let { PRIMARY + it }

    // DATA (API 26 to 28) is the file's absolute path; the result is its parent below the external root in
    // the RELATIVE_PATH shape ("Movies/Fetchr/"), or null outside the root.
    fun relativeOfData(dataPath: String?, externalRoot: String): String? {
        val parent = dataPath?.substringBeforeLast('/', "") ?: return null
        val prefix = externalRoot.trimEnd('/') + "/"
        if (!parent.startsWith(prefix)) return null
        return parent.removePrefix(prefix).trim('/').takeIf { it.isNotEmpty() }?.let { "$it/" }
    }

    fun fromDataPath(dataPath: String?, externalRoot: String): String? =
        fromRelativePath(relativeOfData(dataPath, externalRoot))
}
