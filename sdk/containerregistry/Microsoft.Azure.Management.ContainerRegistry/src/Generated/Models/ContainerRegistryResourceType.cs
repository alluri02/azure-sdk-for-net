// <auto-generated>
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for
// license information.
//
// Code generated by Microsoft (R) AutoRest Code Generator.
// Changes may cause incorrect behavior and will be lost if the code is
// regenerated.
// </auto-generated>

namespace Microsoft.Azure.Management.ContainerRegistry.Models
{
    using Newtonsoft.Json;
    using Newtonsoft.Json.Converters;
    using System.Runtime;
    using System.Runtime.Serialization;

    /// <summary>
    /// Defines values for ContainerRegistryResourceType.
    /// </summary>
    [JsonConverter(typeof(StringEnumConverter))]
    public enum ContainerRegistryResourceType
    {
        [EnumMember(Value = "Microsoft.ContainerRegistry/registries")]
        MicrosoftContainerRegistryRegistries
    }
    internal static class ContainerRegistryResourceTypeEnumExtension
    {
        internal static string ToSerializedValue(this ContainerRegistryResourceType? value)
        {
            return value == null ? null : ((ContainerRegistryResourceType)value).ToSerializedValue();
        }

        internal static string ToSerializedValue(this ContainerRegistryResourceType value)
        {
            switch( value )
            {
                case ContainerRegistryResourceType.MicrosoftContainerRegistryRegistries:
                    return "Microsoft.ContainerRegistry/registries";
            }
            return null;
        }

        internal static ContainerRegistryResourceType? ParseContainerRegistryResourceType(this string value)
        {
            switch( value )
            {
                case "Microsoft.ContainerRegistry/registries":
                    return ContainerRegistryResourceType.MicrosoftContainerRegistryRegistries;
            }
            return null;
        }
    }
}