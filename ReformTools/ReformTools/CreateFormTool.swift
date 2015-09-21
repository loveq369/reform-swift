//
//  CreateFormTool.swift
//  ReformTools
//
//  Created by Laszlo Korte on 17.08.15.
//  Copyright © 2015 Laszlo Korte. All rights reserved.
//

import ReformCore
import ReformMath
import ReformStage

public final class CreateFormTool : Tool {
    
    enum State
    {
        case Idle
        case Started(startPoint: SnapPoint, form: Form, target: Target)
        case Delegating
    }
    
    var state : State = .Idle
    
    var snapType : PointType = [.Form, .Intersection]
    
    let formType : protocol<Form, Creatable>.Type
    
    let selection : FormSelection
    
    let selectionTool : SelectionTool

    let baseName : String
    let nameAllocator : NameAllocator
    let pointSnapper : PointSnapper
    let pointGrabber : PointGrabber
    let streightener : Streightener
    let aligner : Aligner
    let instructionCreator : InstructionCreator
    
    var idSequence : IdentifierSequence<FormIdentifier>
    
    public init(formType : protocol<Form, Creatable>.Type, idSequence : IdentifierSequence<FormIdentifier>, baseName: String, nameAllocator: NameAllocator, selection: FormSelection, pointSnapper: PointSnapper, pointGrabber: PointGrabber, streightener: Streightener, aligner: Aligner, instructionCreator: InstructionCreator, selectionTool: SelectionTool) {
        self.formType = formType
        self.idSequence = idSequence
        self.baseName = baseName
        self.nameAllocator = nameAllocator
        self.selection = selection
        self.selectionTool = selectionTool
        
        self.pointSnapper = pointSnapper
        self.pointGrabber = pointGrabber
        
        self.streightener = streightener
        self.aligner = aligner
        
        self.instructionCreator = instructionCreator
    }
    
    public func setUp() {
        selectionTool.setUp()
        state = .Idle
        pointSnapper.enable(.Any, pointType: snapType)
        pointGrabber.disable()
    }
    
    public func tearDown() {
        instructionCreator.cancel()        
        pointSnapper.disable()
        pointGrabber.disable()
        selectionTool.tearDown()
        state = .Idle
    }
    
    public func refresh() {
        pointSnapper.refresh()
        pointGrabber.refresh()
        selectionTool.refresh()
    }
    
    public func focusChange() {
        selectionTool.focusChange()
    }
    
    public func cancel() {
        switch self.state {
        case .Delegating, .Idle:
            state = .Idle
        case .Started:
            instructionCreator.cancel()
            pointGrabber.disable()
                        
            state = .Idle;
        }
        
        selectionTool.cancel()
    }
    
    public func process(input: Input, atPosition pos: Vec2d, withModifier modifier: Modifier) {
        snapType = modifier.contains(.Glomp) ? [.Glomp] : [.Form, .Intersection]
        
        aligner.setMode(modifier.isAlignOption ? .Centered : .Aligned)
        if modifier.isStreight {
            streightener.enable()
        } else {
            streightener.disable()
        }
        
        switch state {
        case .Delegating:
            selectionTool.process(input, atPosition: pos,  withModifier: modifier)
            switch input {
            case .ModifierChange:
                pointSnapper.enable(.Any, pointType: snapType)
            case .Release:
                state = .Idle
                process(.Move, atPosition: pos, withModifier: modifier)
            case .Cycle, .Toggle, .Move, .Press:
                break
            }
        case .Started(let startPoint, let form, _):
            switch input {
            case .ModifierChange:
                pointSnapper.enable(.Except(form.identifier), pointType: snapType)
                fallthrough
            case .Move:
                pointSnapper.searchAt(pos)
                
                if pointSnapper.current == nil {
                    streightener.reset()
                }
                
                state = .Started(
                    startPoint: startPoint,
                    form: form,
                    target: pointSnapper.getTarget(pos)
                )
            case .Release:
                instructionCreator.commit()
                state = .Idle
                pointSnapper.enable(.Any, pointType: snapType)
                process(.Move, atPosition: pos, withModifier: modifier)
                pointGrabber.disable()
            case .Cycle:
                pointSnapper.cycle()
                state = .Started(
                startPoint: startPoint,
                form: form,
                target: pointSnapper.getTarget(pos)
                )
            case .Toggle:
                streightener.invert()
            case .Press:
                break
            }
        case .Idle:
            switch input {
            case .ModifierChange:
                pointSnapper.enable(.Any, pointType: snapType)
                fallthrough
            case .Move:
                pointSnapper.searchAt(pos)
            case .Press:
                if let startPoint = pointSnapper.current {
                    let form = formType.init(id: idSequence.emitId(), name: self.nameAllocator.alloc(baseName, numbered: true))
                    let destination = RelativeDestination(from: startPoint.runtimePoint, to: startPoint.runtimePoint)
                    let instruction = CreateFormInstruction(form: form, destination: destination)
                    
                    self.instructionCreator.beginCreation(instruction)
                        
                    state = .Started(
                        startPoint: startPoint,
                        form: form,
                        target: .Snap(
                            point: startPoint)
                    )
                    
                    selection.select(form.identifier)
                    pointSnapper.enable(
                        .Except(form.identifier), pointType: snapType)
                    
                    pointGrabber.enable(form.identifier)
                    
                }  else {
                    state = .Delegating
                    selectionTool.process(input, atPosition: pos, withModifier: modifier)
                }
            case .Cycle:
                pointSnapper.cycle()
            case .Toggle, .Release:
                break
            }
        }
        
        publish()
    }
    
    func publish() {
        if case .Started(let start, let form, let target) = state {
            let destination : protocol<RuntimeInitialDestination, Labeled>
            
            switch target {
            case .Free(let targetPosition):
                let delta = streightener.adjust(targetPosition - start.position, step: Angle(degree: 45))
                
                destination = FixSizeDestination(from: start.runtimePoint, delta: delta, alignment: aligner.getAlignment())
                
            case .Snap(let snapPoint):
                destination = RelativeDestination(from: start.runtimePoint, to: snapPoint.runtimePoint, direction: streightener.directionFor(snapPoint.position - start.position), alignment: aligner.getAlignment())

            }
            
            instructionCreator
                .update(CreateFormInstruction(form: form, destination: destination))
        }
    }
    
}
