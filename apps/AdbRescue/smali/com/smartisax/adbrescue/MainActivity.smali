.class public Lcom/smartisax/adbrescue/MainActivity;
.super Landroid/app/Activity;
.source "MainActivity.java"

.field private statusView:Landroid/widget/TextView;

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/app/Activity;-><init>()V

    return-void
.end method

.method protected onCreate(Landroid/os/Bundle;)V
    .locals 8

    invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V

    new-instance v0, Landroid/widget/LinearLayout;

    invoke-direct {v0, p0}, Landroid/widget/LinearLayout;-><init>(Landroid/content/Context;)V

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Landroid/widget/LinearLayout;->setOrientation(I)V

    const/16 v2, 0x30

    invoke-virtual {v0, v2, v2, v2, v2}, Landroid/widget/LinearLayout;->setPadding(IIII)V

    new-instance v3, Landroid/widget/TextView;

    invoke-direct {v3, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V

    iput-object v3, p0, Lcom/smartisax/adbrescue/MainActivity;->statusView:Landroid/widget/TextView;

    const/high16 v4, 0x41800000    # 16.0f

    invoke-virtual {v3, v4}, Landroid/widget/TextView;->setTextSize(F)V

    const-string v5, "USB ADB Rescue\n\nTap Restore ADB, then grant APatch/root if prompted. USB may reconnect."

    invoke-virtual {v3, v5}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V

    invoke-virtual {v0, v3}, Landroid/widget/LinearLayout;->addView(Landroid/view/View;)V

    new-instance v6, Landroid/widget/Button;

    invoke-direct {v6, p0}, Landroid/widget/Button;-><init>(Landroid/content/Context;)V

    const-string v7, "Restore ADB"

    invoke-virtual {v6, v7}, Landroid/widget/Button;->setText(Ljava/lang/CharSequence;)V

    new-instance v1, Lcom/smartisax/adbrescue/MainActivity$1;

    invoke-direct {v1, p0}, Lcom/smartisax/adbrescue/MainActivity$1;-><init>(Lcom/smartisax/adbrescue/MainActivity;)V

    invoke-virtual {v6, v1}, Landroid/widget/Button;->setOnClickListener(Landroid/view/View$OnClickListener;)V

    invoke-virtual {v0, v6}, Landroid/widget/LinearLayout;->addView(Landroid/view/View;)V

    invoke-virtual {p0, v0}, Lcom/smartisax/adbrescue/MainActivity;->setContentView(Landroid/view/View;)V

    return-void
.end method

.method public runRescue()V
    .locals 6

    const-string v0, "Requesting APatch/root. Approve the prompt if it appears."

    invoke-direct {p0, v0}, Lcom/smartisax/adbrescue/MainActivity;->setStatus(Ljava/lang/String;)V

    :try_start_0
    const/4 v0, 0x3

    new-array v0, v0, [Ljava/lang/String;

    const/4 v1, 0x0

    const-string v2, "/system/bin/kp"

    aput-object v2, v0, v1

    const/4 v1, 0x1

    const-string v2, "-c"

    aput-object v2, v0, v1

    const/4 v1, 0x2

    const-string v2, "sh -c 'setprop persist.sys.usb.config mtp,diag,diag_mdm,mass_storage,adb; setprop sys.usb.config mtp,diag,diag_mdm,mass_storage,adb; setprop ctl.restart adbd; sleep 2; getprop sys.usb.state | grep -q adb || setprop sys.usb.config mtp,adb; svc usb setFunctions mtp,adb >/dev/null 2>&1 || true; setprop ctl.restart adbd'"

    aput-object v2, v0, v1

    invoke-static {}, Ljava/lang/Runtime;->getRuntime()Ljava/lang/Runtime;

    move-result-object v1

    invoke-virtual {v1, v0}, Ljava/lang/Runtime;->exec([Ljava/lang/String;)Ljava/lang/Process;

    const-string v0, "Root command launched. If APatch grants it, unplug/replug should not be needed; ADB should reappear after USB reconnects."

    invoke-direct {p0, v0}, Lcom/smartisax/adbrescue/MainActivity;->setStatus(Ljava/lang/String;)V
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v0

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "Failed to launch /system/bin/kp: "

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    move-result-object v1

    invoke-virtual {v0}, Ljava/lang/Exception;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    move-result-object v0

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-direct {p0, v0}, Lcom/smartisax/adbrescue/MainActivity;->setStatus(Ljava/lang/String;)V

    return-void
.end method

.method private setStatus(Ljava/lang/String;)V
    .locals 1

    iget-object v0, p0, Lcom/smartisax/adbrescue/MainActivity;->statusView:Landroid/widget/TextView;

    if-eqz v0, :cond_0

    invoke-virtual {v0, p1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V

    :cond_0
    return-void
.end method
