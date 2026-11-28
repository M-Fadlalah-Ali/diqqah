#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""س232 — مولّد خريطة المفاتيح: يقرأ إفراغ المستخرج (/tmp/dump.txt بخرج
dump حرفياً) ويقترن بالمفاتيح الدلالية المرتبة بالفهرس ذاته فيكتب
scripts/s232_key_map.py بتمثيل Python حرفي — فلا إعادة كتابة يدوية
للقوالب العربية ولا خطر حرف مبدول.

الاستخدام: python3 scripts/s232_gen_keymap.py
الشرط: موافقة العدد 506 حرفياً وإلا فشل بصوت."""
import io
import sys

KEYS = [
    # ===== الفواتير (in) =====
    "receivedLabel", "awaitingDelivery", "awaitingReceipt",
    "noInvoiceWithId", "itemWithNumber", "itemLabel", "quantityLabel",
    "unitPriceLabel", "amountLabel", "noteLabel", "deliveredShort",
    "inDocumentCurrency", "deliveryNoteKeeperCopyTitle", "documentLabel",
    "dateLabel", "partyLabel", "descriptionLabel", "itemNumberLabel",
    "itemNameLabel", "totalQuantities", "delivererLabel", "receiverLabel",
    "paymentLabel", "cashLabel", "onAccountLabel", "statusLabel",
    "draftLabel", "totalLabel", "equivalentIn", "paidLabel",
    "remainingLabel", "salesLabel", "salesAndReturns", "purchasesLabel",
    "purchasesAndReturns", "allStatuses", "draftsLabel", "postedLabel",
    "salesAllFilter", "purchasesAllFilter", "allTypes", "salesTypeFilter",
    "purchasesTypeFilter", "salesInvoiceType", "salesReturnType",
    "purchaseInvoiceType", "purchaseReturnType", "allLabel",
    "notReceived", "partialLabel", "fullyReceived", "postDraftTitle",
    "postDraftBody", "keepAsDraft", "postNow", "invoicePosted",
    "postedWithNumber", "postRejected", "postFailed",
    "newInvoiceChooseType", "newInvoiceOfType", "printFailed",
    "typeLabel", "numberLabel", "partyOrBoxLabel", "receiptLabel",
    "invoicesLog", "invoicesCount", "invoicesLogPdf", "invoicesLogCsv",
    "exportFailed", "invoicesTitle", "printList", "exportCsv",
    "newInvoice", "searchPartyOrNumber", "fromDateLabel", "toDateLabel",
    "viewButton", "noInvoicesYet", "noSearchResults",
    "invoiceDetailsTitle", "quickPrint", "postAction", "printAction",
    "returnNoMatchingOrigin", "invoiceOfNumber", "noParty",
    "orderReferencePrice", "searchSalesInvoiceOrCustomer",
    "searchPurchaseInvoiceOrSupplier", "returnSeedFailed",
    "originReferencePrice", "lastPriceWithParty", "storedPriceOf",
    "levelLabel", "derivedFromBase", "barcodeNotLinked",
    "creditLimitExceededTitle", "creditLimitExceededBody", "backToEdit",
    "saveAnyway", "invoiceFromOrder", "typeFromEntryButton",
    "dateWithFormatHint", "dueDateOptional", "cashCreditExplainer",
    "cashOption", "creditOption", "cashBoxLabel", "balanceNow",
    "suggestionMostUsed", "customerNeedsParty", "supplierNeedsParty",
    "warehouseForGoods", "documentCurrency", "exchangeRateScaleHint",
    "originInvoiceIdRequired", "returnPicker", "descriptionOptional",
    "linesBaseUnitOnly", "addLine", "quickSearchNameCodeBarcode",
    "fullCodeBluetoothHint", "clearBarcode", "selectedCount",
    "selectAllResults", "cancelAction", "addSelected", "inStockShort",
    "invoiceDiscountPercentHint", "draftExplainer",
    "draftHoldsStockNote", "saveAndPost", "saveAsDraft", "noPriceYet",
    "salePriceLabel", "purchasePriceLabel", "availableReady",
    "availableLabel", "availableWithReserved", "serviceSuffix",
    "assemblySuffix", "unitBase", "unitWithFactor", "equivalentInBase",
    "lineTotal", "unitLabel", "baseUnitSuffix", "baseLabel", "inUnit",
    "unitPriceMinorUnit", "lineDiscountOptional", "deleteLine",
    "sumLabel", "discountLabel", "equalsInBase", "deliveryFlagFailed",
    "responsibleSupplierFailed", "postRejectedWithReason",
    "printOrPdf", "sharePdf", "returnFromThisInvoice", "draftBanner",
    "draftSavedBy", "dateAndPayment", "draftSuffix", "totalWithAmount",
    "paidAndRemaining", "equivalentTrailing", "deliverAll", "noLines",
    "countingBasis", "byBasis", "amountWith", "responsibleSupplier",
    "noSupplier", "suggestedLastPurchase",
    # ===== الإعدادات (se) =====
    "appVersionLine", "appTitleWith", "appTitleWithMinor", "noImagesYet",
    "kilobytesCount", "megabytesCount", "custodyCapInvalid",
    "custodyCapSaved", "custodyCapCleared", "counterDigitsRange",
    "counterDigitsSaved", "integrityCheckFailed", "noSessionUser",
    "currentPasswordRequired", "newPasswordRequired",
    "passwordConfirmMismatch", "changePasswordTitle",
    "currentPasswordField", "newPasswordField", "confirmPasswordField",
    "saveNewPassword", "passwordChanged", "filePickerFailed",
    "backupDefaultName", "backupExportFailed", "lockBackupWithPassword",
    "lockBackupExplainer", "eightCharsHint", "passwordWithHint",
    "confirmMismatchShort", "confirmPassword", "revertAction",
    "generateRecoveryCode", "vaultLockFailed", "recoveryCodeTitle",
    "recoveryCodeBody", "recoveryCodeCopied", "copyAction",
    "recordedIt", "recoveryCodeLabel", "recoveryCodeShort", "okAction",
    "vaultRecoveryCode", "vaultRecoveryCodeBody", "removeLockTitle",
    "removeLockExplainer", "removeLockAction", "unencryptedBackup",
    "unencryptedWarning", "continueUnencrypted", "backupCreated",
    "backupFilePlain", "backupFileLocked", "backupFileVaulted",
    "backupFileProgramKey", "backupIncludesImages", "backupNoImages",
    "backupPathLabel", "imagesFileLabel", "exportBackupAction",
    "backupCreateFailed", "chooseBackupPathFirst",
    "restoreBackupTitle", "restoreBackupBody", "continueAction",
    "finalConfirmTitle", "replaceAllConfirm", "safeCancel",
    "finalRestore", "backupContentTitle", "restoreIncludesImages",
    "restoreNoImages", "restoreImagesWillEmpty", "restoreDone",
    "restoreRollbackAt", "restoreRollbackImagesAt", "restoreFailed",
    "imagesBackupCreated", "imagesFileStandalone", "imagesBackupFailed",
    "restoreImagesTitle", "restoreImagesBody", "restoreImagesAction",
    "imagesRestored", "imagesRestoreFailed", "oneMinute",
    "fifteenMinutes", "minutesCount", "idleLockTitle", "idleLockBody",
    "lockAfterIdle", "dataImportTitle", "dataImportBody",
    "dataImportMigrationBody", "openImportScreen", "notCreatedYet",
    "scheduledBackupTitle", "scheduledBackupBody",
    "scheduledBackupPeriods", "trialModeDeferred", "backupQuotaGb",
    "backupsCatalogTitle", "storageManagerTitle", "companyDataTitle",
    "companyDataBody", "companyNameRequired", "phoneLabel",
    "addressLabel", "taxNumberOptional", "companyNameMandatory",
    "companyDataSaved", "saveFailed", "saveAction", "settingsTitle",
    "identitySectionTitle", "currentUser", "lockSwitchUser",
    "changeMyPassword", "dataSecurityTitle", "fullBackupTitle",
    "fullBackupBody", "fullBackupBodyLong", "programKeyEncryption",
    "programKeyDefault", "includeItemImages", "itemImagesSummary",
    "filesCountSuffix", "v3LockedSummary", "v4VaultSummary",
    "v2PlainSummary", "showRecoveryCode", "vaultRecoverySummary",
    "showCodeAction", "createBackupAction", "fullRestoreAction",
    "fullRestoreBody", "backupFilePathLabel", "mobileBrowseHint",
    "chooseBackupFile", "passwordOrCodeHint", "restoreEllipsis",
    "standaloneImagesBackup", "standaloneImagesBody", "copyImagesAction",
    "restoreImagesShort", "integrityChecksTitle", "integrityChecksBody",
    "checkingNow", "checkNowAction", "salesPoliciesTitle",
    "salesDraftsTitle", "salesDraftsBody", "draftsHoldStock",
    "draftsHoldStockBody", "allowDraftOverStock",
    "allowDraftOverStockBody", "agentCollectionsTitle",
    "agentCollectionsBody", "custodyCapLabel", "saveCustodyCap",
    "displaySectionTitle", "displayOptionsTitle",
    "hijriBesideGregorianBody", "hijriBesideGregorian", "previewOf",
    "itemImagesInPrints", "itemImagesInPrintsBody", "appFontTitle",
    "appFontBody", "themeTitle", "themeBody", "operationsTitle",
    "numberingTitle", "numberingBody", "counterDigitsLabel",
    "numberingPreview", "saveCounterDigits", "currenciesTitle",
    "currenciesBody", "diagnosticsTitle", "diagnosticsBody",
    "hideExplanation", "howItWorks",
    # ===== التقارير (re) =====
    "dailyReportsTitle", "financialStatementsTitle", "trialBalanceTitle",
    "trialBalanceDesc", "incomeStatementTitle", "incomeStatementDesc",
    "balanceSheetTitle", "balanceSheetDesc", "booksMatchingTitle",
    "journalBookTitle", "journalBookDesc", "stockLedgerMatchTitle",
    "stockLedgerMatchDesc", "boxesAndReceivablesTitle",
    "boxesReportTitle", "boxesReportDesc", "receivablesPayablesTitle",
    "receivablesPayablesDesc", "agingTitle", "agingDesc",
    "currencyCentersTitle", "currencyCentersDesc",
    "stockAndMovementTitle", "stockReportTitle", "stockReportDesc",
    "itemSalesMovementTitle", "itemSalesMovementDesc",
    "purchasesReportTitle", "purchasesReportDesc", "managementTitle",
    "periodsClosingTitle", "periodsClosingDesc", "accountLabel",
    "debitLabel", "creditLabel", "balanceLabel", "totalDebit",
    "totalCredit", "trialBalanced", "trialNotBalanced",
    "totalsDebitCredit", "trialBalancedFull", "noBoxesYet", "boxLabel",
    "currencyLabel", "activeLabel", "inactiveLabel", "noReceivables",
    "receivablesSide", "payablesSide", "directionLabel", "theyOweUs",
    "weOweThem", "byTypeLabel", "receivableTypeSide", "payableTypeSide",
    "noReceivablesOfType", "receivableFromSales", "payableFromPurchases",
    "agingOf", "agingPeriods", "agingPdf", "theyOweUsOpen",
    "weOweThemOpen", "invoiceNumber", "dueDateWith", "notDue",
    "dueToday", "overdueDays", "noOpenReceivables", "receivableLabel",
    "payableLabel", "totalOf", "invoicesGroupTotal", "stockLabel",
    "generalEntry", "entryLabel", "bookLabel", "bothTotalsBalanced",
    "notBalanced", "journalPdf", "fromDateArabicHint",
    "toDateArabicHint", "noEntriesInRange", "withEntryAndDesc",
    "partyOf", "debitCreditOf", "noStockMovesYet", "byLedgerEntries",
    "byMovements", "varianceLabel", "matchedLabel", "totalByEntries",
    "totalByMovements", "zeroLabel", "matchCorrect",
    "bookVarianceAlert", "entriesVsStock", "matchedCheck", "varianceOf",
    "semicolonSpace", "totalRevenues", "totalExpenses", "netResult",
    "profitOf", "lossOf", "boxesTitle", "boxesBalanceBase",
    "openInvoices", "remainingInvoiceCurrency", "remainingBaseCurrency",
    "totalEquivalentBase", "lastRateRecorded", "itsDate", "baseSuffix",
    "toDateWithFormat", "sideLabel", "totalAssets", "totalLiabilities",
    "totalEquity", "equationBalanced", "equationNotBalanced",
    "assetsLiabilitiesEquity", "assetsLabel", "liabilitiesLabel",
    "equityLabel", "currentPeriodResult", "fromResultAccountsToDate",
    "balanceInStock", "noStockYet", "warehouseLabel", "valueLabel",
    "averageLabel", "unspecifiedLabel", "itemSingular",
    "warehouseAndAverage", "detailLabel", "netLabel",
    "salesReturnsDetail", "netOf", "purchasesReturnsDetail",
    "salesOf", "purchasesOf", "enterRangeThenView",
    "noMovementInRange",
]


def main():
    lines = []
    for raw in io.open("/tmp/dump.txt", encoding="utf-8"):
        lines.append(raw[:-1] if raw.endswith("\n") else raw)
    templates = {}
    for l in lines[1:]:
        if not l.startswith("["):
            continue
        close = l.index(") ")
        idx = int(l[1:l.index("]")])
        t = l[close + 2:].replace("\\n", "\n")
        templates[idx] = t
    if len(templates) != len(KEYS):
        sys.exit("ERR: القوالب %d لا تطابق المفاتيح %d"
                 % (len(templates), len(KEYS)))
    if len(set(KEYS)) != len(KEYS):
        sys.exit("ERR: مفاتيح مكررة")
    out = io.open(
        __file__.replace("s232_gen_keymap.py", "s232_key_map.py"),
        "w", encoding="utf-8")
    out.write('"""س232 — خريطة مفاتيح استخراج النصوص: القالب المعياري'
              ' ← المفتاح.\nمولّدة بscripts/s232_gen_keymap.py من إفراغ'
              ' dump حرفياً — لا تحرَّر يدوياً."""\n\n')
    out.write("KEY_MAP = {\n")
    for i, key in enumerate(KEYS, 1):
        out.write("    %r: %r,\n" % (templates[i], key))
    out.write("}\n")
    out.close()
    print("s232_key_map.py: %d مفتاحاً" % len(KEYS))


if __name__ == "__main__":
    main()
