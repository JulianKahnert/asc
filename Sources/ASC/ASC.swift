//
//  ASC.swift
//  ASC
//
//  Created by Julian Kahnert on 07.11.25.
//

import ArgumentParser

@main
struct ASC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "AppStoreConnect Helper - Manage your App Store Connect versions",
        subcommands: [
            InitCommand.self,
            VersionCommand.self,
            ShowCommand.self,
            SelectBuildCommand.self,
            SubmitCommand.self,
            ListAppsCommand.self,
            ClearCommand.self
        ]
    )
}
