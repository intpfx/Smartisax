.class public Lcom/smartisax/controls/DarkModeTileService;
.super Landroid/service/quicksettings/TileService;


.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/service/quicksettings/TileService;-><init>()V

    return-void
.end method

.method public onClick()V
    .locals 0

    invoke-super {p0}, Landroid/service/quicksettings/TileService;->onClick()V

    invoke-static {p0}, Lcom/smartisax/controls/DarkModeController;->toggle(Landroid/content/Context;)I

    invoke-direct {p0}, Lcom/smartisax/controls/DarkModeTileService;->updateTile()V

    return-void
.end method

.method public onStartListening()V
    .locals 0

    invoke-super {p0}, Landroid/service/quicksettings/TileService;->onStartListening()V

    invoke-direct {p0}, Lcom/smartisax/controls/DarkModeTileService;->updateTile()V

    return-void
.end method

.method private updateTile()V
    .locals 4

    invoke-virtual {p0}, Lcom/smartisax/controls/DarkModeTileService;->getQsTile()Landroid/service/quicksettings/Tile;

    move-result-object v0

    if-eqz v0, :done

    invoke-static {p0}, Lcom/smartisax/controls/DarkModeController;->isDark(Landroid/content/Context;)Z

    move-result v1

    if-eqz v1, :inactive

    const/4 v2, 0x2

    const-string v3, "Dark mode"

    goto :apply

    :inactive
    const/4 v2, 0x1

    const-string v3, "Dark mode"

    :apply
    invoke-virtual {v0, v2}, Landroid/service/quicksettings/Tile;->setState(I)V

    invoke-virtual {v0, v3}, Landroid/service/quicksettings/Tile;->setLabel(Ljava/lang/CharSequence;)V

    invoke-virtual {v0}, Landroid/service/quicksettings/Tile;->updateTile()V

    :done
    return-void
.end method
