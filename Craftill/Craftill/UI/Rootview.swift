import SwiftUI

struct RootView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        ZStack {
            content
            if let d = vm.dialog {
                DialogOverlay(dialog: d)
            }
            if let p = vm.pinPrompt {
                PinOverlay(prompt: p)
            }
        }
        .environmentObject(vm)
        .sheet(isPresented: $vm.showAdhoc) {
            AdhocSheet().environmentObject(vm)
        }
        .frame(minWidth: 1180, minHeight: 760)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.screen {
        case .initialLaunch: InitialLaunchView()
        case .register: cashierContent
        case .menu: MenuView()
        case .edit: EditView()
        case .csvImport: CSVImportView()
        case .report: ReportView()
        case .salesHistory: SalesHistoryView()
        case .stockAdjust: StockAdjustView()
        case .priceList: PriceListView()
        case .sync: SyncView()
        }
    }

    @ViewBuilder
    private var cashierContent: some View {
        switch vm.saleState {
        case .idle, .scanning, .suspended: RegisterView()
        case .choosingPayment: PaymentSelectView()
        case .cashInput: CashEntryView(mixed: false)
        case .satsWaiting: SatsWaitingView()
        case .mixedCashInput: CashEntryView(mixed: true)
        case .done: DoneView()
        }
    }
}