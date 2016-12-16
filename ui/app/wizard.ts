import * as _ from 'lodash';
import {
  Component, Input, Output, EventEmitter, ComponentRef, Injector,
  ViewChild, ViewChildren, ViewContainerRef, ComponentFactoryResolver, ComponentFactory
} from '@angular/core';

import { Modal } from './directives';
import { ErrorService } from './services/error';
import { WizardService } from './services/wizard';
import { BaseModel } from './models';
import { JSONString } from './pipes';
import globals = require('./services/globals');

@Component({
  selector: 'wizard',
  templateUrl: './app/templates/wizard.html'
})
export class WizardComponent {
  model: BaseModel = new BaseModel({data: {}});
  filledModel: BaseModel;
  isSingleStep = false;
  isReadOnly = false;
  @Input() steps: any[] = [];
  @Output() saveHandler = new EventEmitter();
  @ViewChild('step_container', {read: ViewContainerRef}) stepContainer: ViewContainerRef;

  step: number = 0;
  stepComponents: ComponentRef<any>[] = [];

  debug = false;
  jsonTransformer = new JSONString();
  stringified = '';

  constructor(
    private error: ErrorService,
    private modal: Modal,
    private resolver: ComponentFactoryResolver,
    private injector: Injector,
    private wizard: WizardService
  ) {
    wizard.model.subscribe((model: BaseModel) => {
      this.filledModel = model;
    });
  }

  getVisibleSteps() {
    let steps = _.filter(this.stepComponents, (component: any) => {
      return component.instance.isShownInDeck();
    });
    this.isSingleStep = steps.length === 1;
    return steps;
  }

  modelIsValid(): boolean {
    return !_.some(this.getVisibleSteps(), (step: any) => {
      return !step.instance.isValid();
    });
  }

  stepIsValid(): boolean {
    return this.stepComponents[this.step].instance.isValid();
  }

  ngOnInit() {
    this.stepContainer.clear();
    this.steps.forEach((component: any) => {
      let componentFactory: ComponentFactory<any> = this.resolver.resolveComponentFactory(component);
      let componentRef = componentFactory.create(this.injector);
      this.stepContainer.insert(componentRef.hostView);
      this.stepComponents.push(componentRef);
    });
    this.init(new BaseModel({}));
  }

  ngDoCheck() {
    this.stringified = this.jsonTransformer.transform(_.get(this.filledModel, 'data', ''));
  }

  ngOnDestroy() {
    this.stepComponents.forEach((componentRef: ComponentRef<any>) => {
      componentRef.destroy();
    });
  }

  init(model: BaseModel, isReadOnly = false) {
    this.model = model;
    this.isReadOnly = isReadOnly;
    this.stepComponents.forEach((component: any) => {
      component.instance.model = this.model;
      component.instance.init();
    });
    this.step = _.indexOf(this.stepComponents, _.first(this.getVisibleSteps()));
    if (this.step >= 0) {
      this.go();
    }
  }

  renderStep() {
    this.wizard.currentStep.emit(this.stepComponents[this.step]);
  }

  getStep(offset: number): number {
    let visibleSteps = this.getVisibleSteps();
    let visibleIndex = _.indexOf(visibleSteps, this.stepComponents[this.step]);
    let nextIndex = offset + visibleIndex;
    if (visibleIndex < 0 || nextIndex < 0 || nextIndex >= visibleSteps.length) {
      return null;
    }
    return _.indexOf(this.stepComponents, visibleSteps[nextIndex]);
  }

  go(offset: number = 0) {
    let nextIndex = this.getStep(offset);
    if (!_.isNull(nextIndex)) {
      this.step = nextIndex;
      this.renderStep();
    }
  }

  save() {
    this.saveHandler.emit(this.filledModel);
  }
}