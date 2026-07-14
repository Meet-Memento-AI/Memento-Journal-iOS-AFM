//
//  InsightMonthPickerSheet.swift
//  MeetMemento
//
//  Extracted month picker sheet from InsightsView
//

import SwiftUI

struct InsightMonthPickerSheet: View {
    @Environment(\.theme) private var theme

    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    @Binding var isPresented: Bool

    let availableYears: [Int]
    let onDone: () -> Void

    private let monthNames = Calendar.current.monthSymbols

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month and Year Pickers
                HStack(spacing: 0) {
                    // Month Picker
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthNames[month - 1])
                                .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    // Year Picker
                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year))
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 200)
                .padding(.vertical, 20)
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(theme.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDone()
                        isPresented = false
                    }
                    .foregroundStyle(theme.primary)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    @Previewable @State var month = 3
    @Previewable @State var year = 2026
    @Previewable @State var isPresented = true

    Color.clear
        .sheet(isPresented: $isPresented) {
            InsightMonthPickerSheet(
                selectedMonth: $month,
                selectedYear: $year,
                isPresented: $isPresented,
                availableYears: [2026, 2027, 2028],
                onDone: { AppLogger.log("Done pressed") }
            )
            .useTheme()
        }
}
