//
//  ContentView.swift
//  Flute Translator
//
//  Created by Jhala family on 2/10/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var analyzer = AudioAnalyzer()
    @State private var selectedNote = "C"

    var body: some View {
        VStack(spacing: 50) {
            Text("Current Note")
                .font(.title2)
            
            Text(analyzer.currentSargam)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
            
            VStack {
                Text("Base Sa: \(selectedNote)")
                Picker("Base Sa", selection: $selectedNote) {
                    ForEach(["C","D","E","F","G","A","B"], id: \.self) { note in
                        Text(note)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedNote) { newNote in
                    analyzer.setBaseSa(note: newNote)
                }
            }
            
            HStack {
                Button("Start") { analyzer.startAnalyzing() }
                    .padding()
                    .background(Color.green.opacity(0.7))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                
                Button("Stop") { analyzer.stopAnalyzing() }
                    .padding()
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
