.class public Lcom/smartisax/controls/DarkModeController;
.super Ljava/lang/Object;


.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static getMode(Landroid/content/Context;)I
    .locals 2

    const-string v0, "uimode"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/UiModeManager;

    if-eqz v0, :fallback

    invoke-virtual {v0}, Landroid/app/UiModeManager;->getNightMode()I

    move-result v1

    return v1

    :fallback
    const/4 v1, 0x1

    return v1
.end method

.method public static getStatusText(Landroid/content/Context;)Ljava/lang/String;
    .locals 2

    invoke-static {p0}, Lcom/smartisax/controls/DarkModeController;->getMode(Landroid/content/Context;)I

    move-result v0

    const/4 v1, 0x2

    if-ne v0, v1, :light

    const-string v0, "Dark mode is on"

    return-object v0

    :light
    const-string v0, "Dark mode is off"

    return-object v0
.end method

.method public static isDark(Landroid/content/Context;)Z
    .locals 2

    invoke-static {p0}, Lcom/smartisax/controls/DarkModeController;->getMode(Landroid/content/Context;)I

    move-result v0

    const/4 v1, 0x2

    if-ne v0, v1, :light

    const/4 v0, 0x1

    return v0

    :light
    const/4 v0, 0x0

    return v0
.end method

.method public static setMode(Landroid/content/Context;I)V
    .locals 2

    const-string v0, "uimode"

    invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object v0

    check-cast v0, Landroid/app/UiModeManager;

    if-eqz v0, :done

    invoke-virtual {v0, p1}, Landroid/app/UiModeManager;->setNightMode(I)V

    :done
    return-void
.end method

.method public static toggle(Landroid/content/Context;)I
    .locals 2

    invoke-static {p0}, Lcom/smartisax/controls/DarkModeController;->isDark(Landroid/content/Context;)Z

    move-result v0

    if-eqz v0, :set_dark

    const/4 v1, 0x1

    invoke-static {p0, v1}, Lcom/smartisax/controls/DarkModeController;->setMode(Landroid/content/Context;I)V

    return v1

    :set_dark
    const/4 v1, 0x2

    invoke-static {p0, v1}, Lcom/smartisax/controls/DarkModeController;->setMode(Landroid/content/Context;I)V

    return v1
.end method
