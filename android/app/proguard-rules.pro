# Android Release startup: Google Mobile Ads transitively brings in
# androidx.work + Room. AGP/R8 can strip the generated Room database
# constructor, causing androidx.startup.InitializationProvider to crash
# BEFORE the Flutter engine starts:
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
#
# Keep the WorkManager database and the implementation instantiated by
# reflection. Do not disable R8, WorkManager or the Ads SDK.
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
