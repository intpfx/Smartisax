.class final Lcom/smartisax/adbrescue/MainActivity$1;
.super Ljava/lang/Object;
.source "MainActivity.java"

.implements Landroid/view/View$OnClickListener;

.field final synthetic this$0:Lcom/smartisax/adbrescue/MainActivity;

.method constructor <init>(Lcom/smartisax/adbrescue/MainActivity;)V
    .locals 0

    iput-object p1, p0, Lcom/smartisax/adbrescue/MainActivity$1;->this$0:Lcom/smartisax/adbrescue/MainActivity;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public onClick(Landroid/view/View;)V
    .locals 1

    iget-object v0, p0, Lcom/smartisax/adbrescue/MainActivity$1;->this$0:Lcom/smartisax/adbrescue/MainActivity;

    invoke-virtual {v0}, Lcom/smartisax/adbrescue/MainActivity;->runRescue()V

    return-void
.end method
