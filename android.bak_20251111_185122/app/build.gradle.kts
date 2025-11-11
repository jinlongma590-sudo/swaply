// android/app/build.gradle.kts

import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 闂備浇宕垫慨鏉懨洪埡鍜佹晪鐟滄垿濡?key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

android {
    namespace = "com.example.swaply"
    compileSdk = 35

    // 闂?闂傚倸鍊峰ù鍥涢崟顖€鍥ㄥ閹碱厽鏅?NDK 闂傚倷鑳剁划顖炪€冮崨瀛樺亱濠电姴鍋婇懓鍨归悡搴ｆ憼闁哄拋鍓涢埀顒€鍘滈崑鎾绘煕閺囥劋绨界紒杈ㄥ哺濮婅櫣绮欑捄銊ь唶缂備礁顦悘姘辩博閻斿娼ㄩ柍褜鍓熷濠氬Ω閵夈垺鐎婚梺鐟邦嚟閸嬬喖鎮伴妷鈺傚仭?
    ndkVersion = "26.1.10909125"

    defaultConfig {
        applicationId = "com.example.swaply"
        minSdk = 21
        targetSdk = 35
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions { jvmTarget = "11" }

    // 闂?濠电姵顔栭崰妤冩崲閹邦喖绶ら柣锝呮湰椤洟鏌ㄥ☉妯侯伀濡炶濞婇弻鐔碱敍閸℃顏╅柍褜鍓氭繛濠傤潖濞差亜绾ч悹鎭掑壉閵堝鐓熼柕鍫濇噺椤ャ垽鏌℃担鍝バх€规洖銈搁弫鎰償閳╁喚鍟堥梻?key.properties闂?
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        // Debug 闂備礁鎼ˇ顐﹀疾濠婂牆绀夋慨妞诲亾闁靛棔绶氶獮瀣晜閼恒儲鐝繝娈垮枟閿曗晠宕戦崱娑欏仭婵犻潧鐗冮崑鎾斥枔閸喗鐏€闂佺顑嗛幑鍥蓟濞戞鐔哥瑹椤栨艾澹嬬紓鍌氬€搁崐鎼佀囬崹顐＄箚閻庢稒蓱婵潙顪冪€ｎ亝鎹ｉ柟鎻掔秺濮婄儤瀵煎▎鎺濆悈缂備胶濮电敮鈥澄涢崨鏉戠厸闁告侗鍠楀▍鏍⒑閸撴彃浜栭柛搴㈠缁辨挻寰勯幇顓犲幈?闂傚倷鑳堕崑銊╁磿閼碱剛绠旈柨鏇炪€巌nkResources 闂傚倸鍊搁崐绋棵洪悩璇茬；闁规儳鐏堥崑鎾斥枔閸喗鐏€闂佺顑嗛幑鍥蓟?minify闂?闂傚倷鑳堕、濠勭礄娴兼潙纾块柣銏㈩焾閺嬩礁鈹戦悩鍙夊闁?
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        // Release 婵犵數鍋為崹鍫曞箰閹间焦鏅濋柕澶嗘櫆閸婂爼鏌ㄩ弴鐐测偓褰掑疾椤掍焦鍙忔慨妤€妫楁晶鎵棯閹岀吋闁?R8 闂傚倷绀侀幉锟犳晪濡炪倖鍨靛ú銊ф?+ 闂備浇宕垫慨宥夊礃椤垳鐥紓鍌欑贰閻撳牓宕抽敐澶婄畾濞撴埃鍋撻柡浣稿暞缁楃喖鍩€椤掑嫭鍋?
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            // 闂傚倷绀侀崥瀣儑瑜版帒纾块柣銏㈩焾杩濋悗骞垮劚椤︿即宕曟惔顫簻闁哄啫鍊瑰▍鏇熸叏婵犲洨鐣洪柡?proguard-rules.pro闂傚倷鐒︾€笛呯矙閹达附鍤愭い鏍ㄧ缚娴滃綊鏌＄仦璇插姎闁?android/app 婵犵數鍋為崹鍫曞箰閹间緡鏁勯柛娑欐綑閸ㄥ倿鏌涘Δ鍐ㄥ壉闁搞倕鐗撳鍫曟倷閺夋埈妫嗗銈呯箰瀹曨剟鍩ユ径鎰闁告剬鍛櫦闂備礁鐤囬～澶愭偋閻樺樊鍤曟い鎺戝閻愬﹪鏌ㄩ弮鍌滄憘闁?
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.core:core-ktx:1.13.1")
}
// --- 闂傚倷鑳堕…鍫㈡崲閹寸偟绠惧┑鐘叉搐閺嬩焦銇勯幘璺烘灁闁崇懓绉甸妵鍕籍閸屾瀚涘┑鈩冨絻椤兘寮婚妸銉㈡婵炲棙甯掗ˉ婵嬫倵鐟欏嫭鍊愬ù婊嗘硾閻ｅ嘲顫濋懜闈涙疂闂傚倸鐗婃笟妤呭汲閿熺姵鈷戦柛婵嗗婢ф洘銇勯敂钘夘€滈柕鍥ㄥ姍瀹曟﹢鍩￠崘鐐カ闂備礁鎼悧鎾愁焽瑜旈崺銏ｇ疀濞戞瑧鍘藉銈庡亽閸撴瑦淇婄捄銊х＜妞ゆ梹鍎抽崝瀣磼鐎ｎ亶妯€闁糕斁鍋撳銈嗗笒鐎氼參宕?Kotlin 闂傚倷鑳剁划顖炪€冮崨瀛樺亱濠电姴鍋婇懓?---
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlin" && requested.name.startsWith("kotlin-")) {
            // 闂?settings.gradle 婵犵數鍋為崹鍫曞箹閳哄懎鍌ㄥù鐘差儏閸ㄥ倹绻濇繝鍌氼伀妞も晠鏀遍妵鍕箳閸℃ぞ澹曢梻浣风串缁插潡宕戦幘鍓佺煓濠电姴鍟欢鐐差熆鐠洪缚瀚伴柡?1.9.24闂傚倷鐒︾€笛呯矙閹达箑瀚夋い鎺嶇劍濞呯姷鈧箍鍎卞Λ娑€呴悜鑺ョ厪濠㈣泛鐗嗘俊璺ㄧ磼閻樿尙绉烘慨濠冩そ楠炴捇骞掗幋顓燁唲缂傚倷璁查埀顒€鍟块弳锝夋煙?1.9.24
            useVersion("2.0.21")
        }
    }
}