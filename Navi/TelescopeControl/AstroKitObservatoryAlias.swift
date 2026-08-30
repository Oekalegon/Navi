//
//  AstroKitObservatoryAlias.swift
//  Navi
//
//  See INDIObservatory's doc comment in TelescopeSessionManager.swift for why this alias exists:
//  AstroKit and INDIMCPKit both define a type literally named `Observatory`, and each also
//  shadows its own module name with an empty enum of the same name — which defeats a bare
//  `AstroKit.Observatory`/`INDIMCPKit.Observatory` qualification once both modules are imported
//  in the same file. Declared here, in a file that only imports `AstroKit`, where plain
//  `Observatory` is unambiguous.
//

import AstroKit

typealias AstroObservatory = Observatory
