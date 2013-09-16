angular.module('cupcakeDashboard')
  .directive("editable", function() {
    var editorTemplate = '<div class="click-to-edit">' +
        '<div ng-hide="view.editorEnabled">' +
            '{{value}} ' +
            '<a ng-show="auth" class="btn btn-primary btn-xs" ng-click="enableEditor()">Edit</a>' +
        '</div>' +
        '<form ng-show="view.editorEnabled" class="form-inline">' +
            '<input ng-keyup="keyup($event)" class="form-control col-lg-2" ng-model="view.editableValue">' +
            '<a class="btn btn-primary btn-xs" ng-click="disableEditor()">Cancel</a>' +
        '</form>' +
    '</div>';

    return {
        restrict: "A",
        replace: true,
        template: editorTemplate,
        scope: {
            value: "=editable",
            callback: "&",
            property: "@editable",
            auth: "="
        },
        controller: function($scope) {
            if(!$scope.value)
            {
                $scope.value = '';
            }
            $scope.view = {
                editableValue: $scope.value,
                editorEnabled: false
            };

            $scope.enableEditor = function() {
                $scope.view.editorEnabled = true;
                $scope.view.editableValue = $scope.value;
                $scope.view.auth = $scope.auth;
            };

            $scope.disableEditor = function() {
                $scope.view.editorEnabled = false;
            };

            $scope.save = function(data) {
                if(!$scope.view.editorEnabled){
                    return;
                }
                $scope.disableEditor();
                $scope.value = $scope.view.editableValue;
                obj = {}
                obj[$scope.property] = $scope.value
                $scope.callback({data: {path: $scope.property, value: $scope.value}});
            };


            $scope.keyup = function(e){
                if(e.keyCode == 13) // enter
                {
                    $scope.save();
                }
                else if (e.keyCode == 27) // escape
                {
                    $scope.disableEditor();
                }
            }

        }
    };
});
