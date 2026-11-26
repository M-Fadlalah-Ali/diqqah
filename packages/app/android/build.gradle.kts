allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// D-056 على CI (Task 50): file_picker 8.3.7 تُجمَّع ضد android-34 بينما
// flutter_plugin_android_lifecycle 2.0.35 يشترط 36 فأكثر — فيرفض مدقق
// AAR وحدة file_picker نفسها (وحدة التطبيق أعلى بالفعل). الحل المعياري:
// رفع تجميع كل وحدات أندرويد الفرعية إلى 36. compileSdk إعداد تجميع
// بحت: لا يغيّر سلوك التشغيل ولا أجهزة التشغيل (minSdk/targetSdk بلا
// مساس). عمداً بالانعكاس: جذر المشروع لا يرى أصناف AGP (الإضافات
// معلنة apply false في settings) فلا يصح الإشارة إليها بالاسم.
// وإلزاماً بالترتيب: التسجيل هنا قبل كتلة evaluationDependsOn أدناه —
// فهي تجبر تقييم :app فوراً، وبعدها يرمى «already evaluated» (Task 50).
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        androidExt.javaClass.methods
            .firstOrNull { it.name == "setCompileSdk" }
            ?.invoke(androidExt, 36)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
